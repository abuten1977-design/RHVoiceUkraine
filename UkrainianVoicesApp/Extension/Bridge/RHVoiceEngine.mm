//
//  RHVoiceEngine.mm
//  Ukrainian Voices Extension
//

#import "RHVoiceEngine.h"
#include "RHVoice.h"
#import <AVFoundation/AVFoundation.h>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <atomic>

// MARK: - ThreadSafeAudioQueue

class ThreadSafeAudioQueue {
public:
    // Не копіюємо — mutex не копіюється
    ThreadSafeAudioQueue() = default;
    ThreadSafeAudioQueue(const ThreadSafeAudioQueue&) = delete;
    ThreadSafeAudioQueue& operator=(const ThreadSafeAudioQueue&) = delete;

    void push(const short* data, size_t count) {
        if (cancelled.load()) return;
        NSData* chunk = [NSData dataWithBytes:data length:count * sizeof(short)];
        {
            std::lock_guard<std::mutex> lock(mtx);
            queue.push_back(chunk);
        }
        cv.notify_one();
    }

    NSData* pop() {
        std::unique_lock<std::mutex> lock(mtx);
        cv.wait(lock, [this] { return !queue.empty() || finished || cancelled.load(); });
        if (queue.empty()) return nil;
        NSData* chunk = queue.front();
        queue.pop_front();
        return chunk;
    }

    void set_finished() {
        {
            std::lock_guard<std::mutex> lock(mtx);
            finished = true;
        }
        cv.notify_all();
    }

    void cancel() {
        cancelled.store(true);
        {
            std::lock_guard<std::mutex> lock(mtx);
            finished = true;
            queue.clear();
        }
        cv.notify_all();
    }

    bool is_cancelled() const { return cancelled.load(); }

private:
    std::mutex mtx;
    std::condition_variable cv;
    std::deque<NSData*> queue;
    bool finished = false;
    std::atomic<bool> cancelled{false};
};

// MARK: - @interface (до callbacks щоб вони бачили properties)

@interface RHVoiceEngine ()
@property (assign) RHVoice_tts_engine engine;
@property (assign) BOOL initialized;
@property (assign) int currentSampleRate;
@property (assign) BOOL cancelRequested;
@property (strong, nullable) NSMutableData *audioBuffer;
@property (assign) ThreadSafeAudioQueue* audioQueue;
@end

// MARK: - C Callbacks (після @interface — бачать properties)

static int set_sample_rate_callback(int sample_rate, void* user_data) {
    if (!user_data) return 1;
    RHVoiceEngine* engine = (__bridge RHVoiceEngine*)user_data;
    engine.currentSampleRate = sample_rate;
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    if (!user_data) return 1;
    RHVoiceEngine* engine = (__bridge RHVoiceEngine*)user_data;
    if (engine.cancelRequested) return 0;

    ThreadSafeAudioQueue* q = engine.audioQueue;
    if (q) {
        if (q->is_cancelled()) return 0;
        q->push(samples, count);
    } else {
        [engine.audioBuffer appendBytes:samples length:count * sizeof(short)];
    }
    return 1;
}

// MARK: - @implementation

@implementation RHVoiceEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        _engine = NULL;
        _currentSampleRate = 0;
        _cancelRequested = NO;
        _audioBuffer = nil;
        _audioQueue = nullptr;
        [self initializeEngine];
    }
    return self;
}

- (BOOL)initializeEngine {
    if (self.initialized) return YES;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *voicesPath = [[bundle resourcePath] stringByAppendingPathComponent:@"Voices"];

    BOOL isDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:voicesPath isDirectory:&isDir] || !isDir) {
        voicesPath = [bundle pathForResource:@"Voices" ofType:nil];
        if (!voicesPath) { NSLog(@"❌ Voices not found"); return NO; }
    }

    NSLog(@"✅ Voices: %@", voicesPath);

    RHVoice_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;

    RHVoice_init_params params;
    memset(&params, 0, sizeof(params));
    params.data_path = [voicesPath UTF8String];
    params.config_path = [voicesPath UTF8String];
    params.callbacks = callbacks;

    self.engine = RHVoice_new_tts_engine(&params);
    if (!self.engine) { NSLog(@"❌ Engine init failed"); return NO; }

    self.initialized = YES;
    NSLog(@"✅ Engine ready");
    return YES;
}

- (RHVoice_message)buildMessage:(NSString*)text voice:(NSString*)voice
                           rate:(double)rate volume:(double)volume pitch:(double)pitch {
    RHVoice_synth_params p;
    memset(&p, 0, sizeof(p));
    p.voice_profile = [voice UTF8String];
    p.absolute_rate = rate - 1.0;
    p.relative_rate = rate;
    p.absolute_pitch = pitch - 1.0;
    p.relative_pitch = pitch;
    p.relative_volume = volume;

    const char* t = [text UTF8String];
    return RHVoice_new_message(self.engine, t, (unsigned int)strlen(t),
                               RHVoice_message_text, &p,
                               (__bridge void*)self);
}

// MARK: - Sync synthesize (для preview в App)

- (nullable AVAudioPCMBuffer*)synthesize:(NSString*)text voice:(NSString*)voice
                                    rate:(double)rate volume:(double)volume pitch:(double)pitch {
    if (!self.initialized || !text.length) return nil;

    self.cancelRequested = NO;
    self.audioQueue = nullptr;
    self.audioBuffer = [NSMutableData new];
    self.currentSampleRate = 0;

    RHVoice_message msg = [self buildMessage:text voice:voice rate:rate volume:volume pitch:pitch];
    if (!msg) return nil;

    RHVoice_speak(msg);
    RHVoice_delete_message(msg);

    NSData* buf = self.audioBuffer;
    int sr = self.currentSampleRate;
    self.audioBuffer = nil;

    if (!buf.length || sr == 0) return nil;
    return [self pcmBufferFrom:buf sampleRate:sr];
}

// MARK: - Streaming synthesize (для VoiceOver Extension)

- (void)synthesizeStreaming:(NSString*)text voice:(NSString*)voice
                      rate:(double)rate volume:(double)volume pitch:(double)pitch
                   onChunk:(void(^)(const short* samples, unsigned int count, int sampleRate))chunkCallback {
    if (!self.initialized || !text.length) return;

    // Створюємо чергу на heap щоб уникнути проблем з копіюванням
    ThreadSafeAudioQueue* queue = new ThreadSafeAudioQueue();
    self.cancelRequested = NO;
    self.audioQueue = queue;
    self.audioBuffer = nil;
    self.currentSampleRate = 0;

    // Синтез в background
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RHVoice_message msg = [self buildMessage:text voice:voice rate:rate volume:volume pitch:pitch];
        if (msg) {
            RHVoice_speak(msg);
            RHVoice_delete_message(msg);
        }
        queue->set_finished();
    });

    // Consumer loop
    while (true) {
        NSData* chunk = queue->pop();
        if (!chunk) break;
        const short* samples = (const short*)chunk.bytes;
        unsigned int count = (unsigned int)(chunk.length / sizeof(short));
        int sr = self.currentSampleRate > 0 ? self.currentSampleRate : 24000;
        chunkCallback(samples, count, sr);
    }

    self.audioQueue = nullptr;
    delete queue;
}

- (void)cancel {
    self.cancelRequested = YES;
    ThreadSafeAudioQueue* q = self.audioQueue;
    if (q) q->cancel();
}

// MARK: - Int16 → Float32

- (AVAudioPCMBuffer*)pcmBufferFrom:(NSData*)data sampleRate:(int)sr {
    AVAudioFormat* fmt = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatFloat32
                  sampleRate:sr channels:1 interleaved:NO];
    if (!fmt) return nil;

    AVAudioFrameCount frames = (AVAudioFrameCount)(data.length / sizeof(short));
    AVAudioPCMBuffer* buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:frames];
    if (!buf) return nil;

    buf.frameLength = frames;
    const short* src = (const short*)data.bytes;
    float* dst = buf.floatChannelData[0];
    for (AVAudioFrameCount i = 0; i < frames; i++) {
        dst[i] = src[i] / 32768.0f;
    }
    return buf;
}

- (void)dealloc {
    if (self.engine) {
        RHVoice_delete_tts_engine(self.engine);
    }
}

@end
