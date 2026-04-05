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

template<size_t Capacity = 1024>
class AudioRingBuffer {
public:
    AudioRingBuffer() = default;
    AudioRingBuffer(const AudioRingBuffer&) = delete;
    AudioRingBuffer& operator=(const AudioRingBuffer&) = delete;

    bool push(__unsafe_unretained NSData* value) {
        const size_t currentWrite = writeIndex.load(std::memory_order_relaxed);
        const size_t nextWrite = (currentWrite + 1) % Capacity;
        if (nextWrite == readIndex.load(std::memory_order_acquire)) {
            return false; // full
        }
        buffer[currentWrite] = value;
        writeIndex.store(nextWrite, std::memory_order_release);
        return true;
    }

    bool pop(__unsafe_unretained NSData* __strong & value) {
        const size_t currentRead = readIndex.load(std::memory_order_relaxed);
        if (currentRead == writeIndex.load(std::memory_order_acquire)) {
            return false; // empty
        }
        value = buffer[currentRead];
        buffer[currentRead] = nil;
        readIndex.store((currentRead + 1) % Capacity, std::memory_order_release);
        return true;
    }

    bool is_empty() const {
        return readIndex.load(std::memory_order_acquire) == writeIndex.load(std::memory_order_acquire);
    }

private:
    std::atomic<size_t> writeIndex{0};
    std::atomic<size_t> readIndex{0};
    __strong NSData* buffer[Capacity];
};

// MARK: - Engine state (heap-allocated, passed via user_data)

struct EngineState {
    AudioRingBuffer<1024>* queue;
    std::atomic<bool> cancelled;
    std::atomic<int> sampleRate;
    
    EngineState() : queue(nullptr), cancelled(false), sampleRate(0) {}
    EngineState(const EngineState&) = delete;
    EngineState& operator=(const EngineState&) = delete;
};

// MARK: - C Callbacks

static int set_sample_rate_callback(int sample_rate, void* user_data) {
    if (!user_data) return 1;
    EngineState* state = static_cast<EngineState*>(user_data);
    state->sampleRate.store(sample_rate, std::memory_order_release);
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    if (!user_data) return 1;
    EngineState* state = static_cast<EngineState*>(user_data);
    
    if (state->cancelled.load(std::memory_order_acquire)) {
        return 0;
    }
    
    NSData* chunk = [NSData dataWithBytes:samples length:count * sizeof(short)];
    // Spin until space available (max 200 * 500us = 100ms)
    for (int i = 0; i < 200; i++) {
        if (state->queue->push(chunk)) return 1;
        usleep(500);
    }
    return 1; // drop if still full
}

// MARK: - @interface

@interface RHVoiceEngine ()
@property (assign) RHVoice_tts_engine engine;
@property (assign) BOOL initialized;
@end

// MARK: - @implementation

@implementation RHVoiceEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        _engine = NULL;
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

// MARK: - Sync synthesize (для preview в App)

- (nullable AVAudioPCMBuffer*)synthesize:(NSString*)text voice:(NSString*)voice
                                    rate:(double)rate volume:(double)volume pitch:(double)pitch {
    if (!self.initialized || !text.length) return nil;

    AudioRingBuffer<1024> queue;
    EngineState state;
    state.queue = &queue;

    RHVoice_synth_params p;
    memset(&p, 0, sizeof(p));
    p.voice_profile = [voice UTF8String];
    p.absolute_rate = rate - 1.0;
    p.relative_rate = rate;
    p.absolute_pitch = pitch - 1.0;
    p.relative_pitch = pitch;
    p.relative_volume = volume;

    const char* t = [text UTF8String];
    RHVoice_message msg = RHVoice_new_message(self.engine, t, (unsigned int)strlen(t),
                                              RHVoice_message_text, &p, &state);
    if (!msg) return nil;

    RHVoice_speak(msg);
    RHVoice_delete_message(msg);

    // Collect all chunks
    NSMutableData* audioBuffer = [NSMutableData new];
    NSData* chunk;
    while (queue.pop(chunk)) {
        if (chunk) [audioBuffer appendData:chunk];
    }

    int sr = state.sampleRate.load(std::memory_order_acquire);
    if (sr == 0) sr = 24000;
    if (!audioBuffer.length) return nil;
    return [self pcmBufferFrom:audioBuffer sampleRate:sr];
}

// MARK: - Streaming synthesize (для VoiceOver Extension)

- (void)synthesizeStreaming:(NSString*)text voice:(NSString*)voice
                      rate:(double)rate volume:(double)volume pitch:(double)pitch
                   onChunk:(void(^)(const short* samples, unsigned int count, int sampleRate))chunkCallback {
    if (!self.initialized || !text.length) return;

    AudioRingBuffer<1024>* queue = new AudioRingBuffer<1024>();
    EngineState* state = new EngineState();
    state->queue = queue;

    RHVoice_synth_params p;
    memset(&p, 0, sizeof(p));
    p.voice_profile = [voice UTF8String];
    p.absolute_rate = rate - 1.0;
    p.relative_rate = rate;
    p.absolute_pitch = pitch - 1.0;
    p.relative_pitch = pitch;
    p.relative_volume = volume;

    const char* t = [text UTF8String];
    RHVoice_message msg = RHVoice_new_message(self.engine, t, (unsigned int)strlen(t),
                                              RHVoice_message_text, &p, state);
    if (!msg) {
        delete state;
        delete queue;
        return;
    }

    // Synthesis in background — callbacks write to queue
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RHVoice_speak(msg);
        RHVoice_delete_message(msg);
        // Push nil sentinel to signal completion
        NSData* sentinel = nil;
        for (int i = 0; i < 200; i++) {
            if (queue->push(sentinel)) break;
            usleep(500);
        }
    });

    // Consumer loop with spin-wait (200 retries × 500μs = max 100ms per chunk)
    while (true) {
        NSData* chunk = nil;
        bool gotData = false;

        for (int attempt = 0; attempt < 200; attempt++) {
            if (state->cancelled.load(std::memory_order_acquire)) goto done;
            if (queue->pop(chunk)) { gotData = true; break; }
            usleep(500);
        }

        if (!gotData || !chunk) break; // timeout or sentinel

        const short* samples = (const short*)chunk.bytes;
        unsigned int count = (unsigned int)(chunk.length / sizeof(short));
        int sr = state->sampleRate.load(std::memory_order_acquire);
        if (sr == 0) sr = 24000;
        chunkCallback(samples, count, sr);
    }

done:
    delete state;
    delete queue;
}

- (void)cancel {
    // cancel is handled via EngineState per-call; no global state needed
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
