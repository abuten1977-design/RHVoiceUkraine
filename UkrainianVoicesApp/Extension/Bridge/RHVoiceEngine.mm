//
//  RHVoiceEngine.mm
//  Ukrainian Voices Extension
//

#import "RHVoiceEngine.h"
#include "RHVoice.h"
#import <AVFoundation/AVFoundation.h>
#include <atomic>
#include <cstdint>
#include <cstring>

// MARK: - ThreadSafeRingBuffer (lock-free, atomic-based)

template<typename T, size_t Capacity = 1024>
class ThreadSafeRingBuffer {
public:
    ThreadSafeRingBuffer() = default;
    ThreadSafeRingBuffer(const ThreadSafeRingBuffer&) = delete;
    ThreadSafeRingBuffer& operator=(const ThreadSafeRingBuffer&) = delete;

    bool push(const T& value) {
        const size_t currentWrite = writeIndex.load(std::memory_order_relaxed);
        const size_t nextWrite = (currentWrite + 1) % Capacity;
        
        // Buffer full?
        if (nextWrite == readIndex.load(std::memory_order_acquire)) {
            return false;
        }
        
        buffer[currentWrite] = value;
        writeIndex.store(nextWrite, std::memory_order_release);
        return true;
    }

    bool pop(T& value) {
        const size_t currentRead = readIndex.load(std::memory_order_relaxed);
        
        // Buffer empty?
        if (currentRead == writeIndex.load(std::memory_order_acquire)) {
            return false;
        }
        
        value = buffer[currentRead];
        readIndex.store((currentRead + 1) % Capacity, std::memory_order_release);
        return true;
    }

    bool is_empty() const {
        return readIndex.load(std::memory_order_acquire) == writeIndex.load(std::memory_order_acquire);
    }

    void reset() {
        writeIndex.store(0, std::memory_order_release);
        readIndex.store(0, std::memory_order_release);
    }

private:
    std::atomic<size_t> writeIndex{0};
    std::atomic<size_t> readIndex{0};
    T buffer[Capacity];
};

// MARK: - Engine state structure (passed to callbacks)

struct EngineState {
    ThreadSafeRingBuffer<NSData*>* queue;
    std::atomic<bool> cancelled{false};
    int* sampleRate;
    int maxRetries;
    int retryDelayMicroseconds;
};

// MARK: - Global state for callbacks (single instance per engine)

static __thread EngineState* tls_engineState = nullptr;

// MARK: - C Callbacks

static int set_sample_rate_callback(int sample_rate, void* user_data) {
    if (!tls_engineState) return 1;
    if (tls_engineState->sampleRate) {
        *tls_engineState->sampleRate = sample_rate;
    }
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    if (!tls_engineState) return 1;
    
    if (tls_engineState->cancelled.load(std::memory_order_acquire)) {
        return 0;
    }
    
    NSData* chunk = [NSData dataWithBytes:samples length:count * sizeof(short)];
    if (!tls_engineState->queue->push(chunk)) {
        // Buffer full - drop chunk (shouldn't happen with proper sizing)
        return 0;
    }
    
    return 1;
}

// MARK: - @interface

@interface RHVoiceEngine ()
@property (assign) RHVoice_tts_engine engine;
@property (assign) BOOL initialized;
@property (assign) int currentSampleRate;
@property (assign) BOOL cancelRequested;
@end

// MARK: - @implementation

@implementation RHVoiceEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        _engine = NULL;
        _currentSampleRate = 0;
        _cancelRequested = NO;
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
    self.currentSampleRate = 0;

    NSMutableData* audioBuffer = [NSMutableData new];

    // For sync mode, use simple blocking approach
    // (preview is not in render thread, so mutex is acceptable)
    ThreadSafeRingBuffer<NSData*, 64> queue;
    int sampleRate = 0;

    EngineState state;
    state.queue = &queue;
    state.cancelled.store(false, std::memory_order_release);
    state.sampleRate = &sampleRate;
    state.maxRetries = 200;
    state.retryDelayMicroseconds = 500;

    tls_engineState = &state;

    RHVoice_message msg = [self buildMessage:text voice:voice rate:rate volume:volume pitch:pitch];
    if (!msg) {
        tls_engineState = nullptr;
        return nil;
    }

    RHVoice_speak(msg);
    RHVoice_delete_message(msg);

    tls_engineState = nullptr;

    // Collect all chunks from queue
    NSData* chunk;
    while (queue.pop(chunk)) {
        if (chunk) {
            [audioBuffer appendData:chunk];
        }
    }

    int sr = sampleRate > 0 ? sampleRate : 24000;

    if (!audioBuffer.length || sr == 0) return nil;
    return [self pcmBufferFrom:audioBuffer sampleRate:sr];
}

// MARK: - Streaming synthesize (для VoiceOver Extension)

- (void)synthesizeStreaming:(NSString*)text voice:(NSString*)voice
                      rate:(double)rate volume:(double)volume pitch:(double)pitch
                   onChunk:(void(^)(const short* samples, unsigned int count, int sampleRate))chunkCallback {
    if (!self.initialized || !text.length) return;

    self.cancelRequested = NO;

    // Create queue on heap
    ThreadSafeRingBuffer<NSData*, 1024>* queue = new ThreadSafeRingBuffer<NSData*, 1024>();
    int sampleRate = 0;

    EngineState state;
    state.queue = queue;
    state.cancelled.store(false, std::memory_order_release);
    state.sampleRate = &sampleRate;
    state.maxRetries = 200;
    state.retryDelayMicroseconds = 500;

    tls_engineState = &state;

    RHVoice_message msg = [self buildMessage:text voice:voice rate:rate volume:volume pitch:pitch];
    if (!msg) {
        tls_engineState = nullptr;
        delete queue;
        return;
    }

    // Start synthesis in background
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RHVoice_speak(msg);
        RHVoice_delete_message(msg);
        
        // Signal completion by pushing nil sentinel
        NSData* sentinel = nil;
        queue->push(sentinel);
        
        tls_engineState = nullptr;
    });

    // Consumer loop with spin-wait
    while (true) {
        NSData* chunk = nil;
        bool gotData = false;
        
        for (int attempt = 0; attempt < state.maxRetries; attempt++) {
            if (state.cancelled.load(std::memory_order_acquire)) {
                break;
            }
            
            if (queue->pop(chunk)) {
                gotData = true;
                break;
            }
            
            // Spin-wait: small delay before retry
            if (attempt < state.maxRetries - 1) {
                usleep(state.retryDelayMicroseconds);
            }
        }
        
        if (!gotData || !chunk) {
            break;
        }
        
        // Check for sentinel (nil chunk means end)
        if (chunk.length == 0) {
            break;
        }
        
        const short* samples = (const short*)chunk.bytes;
        unsigned int count = (unsigned int)(chunk.length / sizeof(short));
        int sr = sampleRate > 0 ? sampleRate : 24000;
        chunkCallback(samples, count, sr);
    }

    delete queue;
}

- (void)cancel {
    self.cancelRequested = YES;
    // Note: For streaming mode, we'd need to track the EngineState pointer
    // For now, this only affects sync mode via cancelRequested flag
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
