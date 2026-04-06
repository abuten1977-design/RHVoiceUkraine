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

// MARK: - ThreadSafeRingBuffer (lock-free, SPSC atomic)

template<typename T, size_t Capacity = 1024>
class ThreadSafeRingBuffer {
public:
    ThreadSafeRingBuffer() = default;
    ThreadSafeRingBuffer(const ThreadSafeRingBuffer&) = delete;
    ThreadSafeRingBuffer& operator=(const ThreadSafeRingBuffer&) = delete;

    bool push(T value) {
        const size_t w = writeIndex.load(std::memory_order_relaxed);
        const size_t next = (w + 1) % Capacity;
        if (next == readIndex.load(std::memory_order_acquire)) return false; // full
        buffer[w] = value;
        writeIndex.store(next, std::memory_order_release);
        return true;
    }

    bool pop(T& value) {
        const size_t r = readIndex.load(std::memory_order_relaxed);
        if (r == writeIndex.load(std::memory_order_acquire)) return false; // empty
        value = buffer[r];
        readIndex.store((r + 1) % Capacity, std::memory_order_release);
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

// MARK: - EngineState (heap-allocated, shared between C callback and ObjC)

struct EngineState {
    ThreadSafeRingBuffer<void*>* queue;
    std::atomic<bool> cancelled{false};
    std::atomic<int> sampleRate{24000};
    std::atomic<bool> synthesisDone{false};
    NSCondition* dataCondition; // Condition variable to wake consumer when data arrives
};

// MARK: - Thread-local pointer to current EngineState

static __thread EngineState* tls_engineState = nullptr;

// MARK: - C Callbacks

static int set_sample_rate_callback(int sample_rate, void* user_data) {
    if (tls_engineState) {
        tls_engineState->sampleRate.store(sample_rate, std::memory_order_release);
    }
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    if (!tls_engineState) return 1;
    if (tls_engineState->cancelled.load(std::memory_order_acquire)) return 0;

    NSData* chunk = [NSData dataWithBytes:samples length:count * sizeof(short)];
    void* retained = (__bridge_retained void*)chunk;

    // If ring buffer is full, drop chunk rather than block
    if (!tls_engineState->queue->push(retained)) {
        CFBridgingRelease(retained);
        return 1;
    }
    
    // Signal consumer that data is available
    [tls_engineState->dataCondition lock];
    [tls_engineState->dataCondition signal];
    [tls_engineState->dataCondition unlock];
    
    return 1;
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

    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSString* voicesPath = [[bundle resourcePath] stringByAppendingPathComponent:@"Voices"];

    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:voicesPath isDirectory:&isDir] || !isDir) {
        voicesPath = [bundle pathForResource:@"Voices" ofType:nil];
        if (!voicesPath) {
            // Fallback: try main bundle (for App target, not Extension)
            NSBundle* mainBundle = [NSBundle mainBundle];
            voicesPath = [[mainBundle resourcePath] stringByAppendingPathComponent:@"Voices"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:voicesPath isDirectory:&isDir] || !isDir) {
                voicesPath = [mainBundle pathForResource:@"Voices" ofType:nil];
                if (!voicesPath) {
                    NSLog(@"❌ Voices not found in bundleForClass or mainBundle");
                    return NO;
                }
            }
        }
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
    NSLog(@"🔍 synthesize called: initialized=%d, text='%@', voice='%@'", self.initialized, text, voice);
    
    if (!self.initialized || !text.length) {
        NSLog(@"❌ synthesize failed: initialized=%d, textLength=%lu", self.initialized, (unsigned long)text.length);
        return nil;
    }

    ThreadSafeRingBuffer<void*> queue;
    EngineState state;
    state.queue = &queue;
    state.cancelled.store(false, std::memory_order_release);
    state.sampleRate.store(24000, std::memory_order_release);
    state.synthesisDone.store(false, std::memory_order_release);
    state.dataCondition = nil; // Not used in sync mode

    // Set TLS in current thread — RHVoice_speak is synchronous, callbacks fire here
    tls_engineState = &state;

    RHVoice_message msg = [self buildMessage:text voice:voice rate:rate volume:volume pitch:pitch];
    if (!msg) {
        NSLog(@"❌ buildMessage failed for voice '%@'", voice);
        tls_engineState = nullptr;
        return nil;
    }

    RHVoice_speak(msg);
    RHVoice_delete_message(msg);
    tls_engineState = nullptr;

    // Collect all chunks
    NSMutableData* audioBuffer = [NSMutableData new];
    void* chunkPtr;
    while (queue.pop(chunkPtr)) {
        if (chunkPtr) {
            NSData* chunk = (__bridge_transfer NSData*)chunkPtr;
            [audioBuffer appendData:chunk];
        }
    }

    if (!audioBuffer.length) {
        NSLog(@"❌ No audio data synthesized");
        return nil;
    }

    int sr = state.sampleRate.load(std::memory_order_acquire);
    if (sr <= 0) sr = 24000;
    
    NSLog(@"✅ Synthesized %lu bytes at %d Hz", (unsigned long)audioBuffer.length, sr);
    return [self pcmBufferFrom:audioBuffer sampleRate:sr];
}

// MARK: - Streaming synthesize (для VoiceOver Extension)
// Producer: RHVoice_speak runs in background thread, callbacks push to ring buffer.
// Consumer: caller's thread (synthesizeSpeechRequest background queue) drains ring buffer.
// NSCondition wakes consumer when data arrives — no spin-lock, no CPU burn.

- (void)synthesizeStreaming:(NSString*)text voice:(NSString*)voice
                      rate:(double)rate volume:(double)volume pitch:(double)pitch
                   onChunk:(void(^)(const short* samples, unsigned int count, int sampleRate))chunkCallback {
    if (!self.initialized || !text.length) return;

    // Heap-allocated — lifetime spans both producer and consumer
    EngineState* state = new EngineState();
    state->queue = new ThreadSafeRingBuffer<void*>();
    state->cancelled.store(false, std::memory_order_release);
    state->sampleRate.store(24000, std::memory_order_release);
    state->synthesisDone.store(false, std::memory_order_release);
    state->dataCondition = [[NSCondition alloc] init];

    NSString* textCopy = [text copy];
    NSString* voiceCopy = [voice copy];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // TLS set in THIS thread — callbacks fire synchronously from RHVoice_speak here
        tls_engineState = state;

        RHVoice_message msg = [self buildMessage:textCopy voice:voiceCopy
                                            rate:rate volume:volume pitch:pitch];
        if (msg) {
            RHVoice_speak(msg);
            RHVoice_delete_message(msg);
        }

        tls_engineState = nullptr;
        // Signal consumer that production is complete
        state->synthesisDone.store(true, std::memory_order_release);
        [state->dataCondition lock];
        [state->dataCondition broadcast];
        [state->dataCondition unlock];
    });

    // Consumer loop — sleeps on NSCondition until data arrives or synthesis done
    while (true) {
        void* chunkPtr = nullptr;
        if (state->queue->pop(chunkPtr)) {
            NSData* chunk = (__bridge_transfer NSData*)chunkPtr;
            const short* samples = (const short*)chunk.bytes;
            unsigned int count = (unsigned int)(chunk.length / sizeof(short));
            int sr = state->sampleRate.load(std::memory_order_acquire);
            if (sr <= 0) sr = 24000;
            chunkCallback(samples, count, sr);
        } else if (state->synthesisDone.load(std::memory_order_acquire)) {
            // Drain any remaining chunks after done signal
            while (state->queue->pop(chunkPtr)) {
                if (chunkPtr) {
                    NSData* chunk = (__bridge_transfer NSData*)chunkPtr;
                    const short* samples = (const short*)chunk.bytes;
                    unsigned int count = (unsigned int)(chunk.length / sizeof(short));
                    int sr = state->sampleRate.load(std::memory_order_acquire);
                    if (sr <= 0) sr = 24000;
                    chunkCallback(samples, count, sr);
                }
            }
            break;
        } else {
            // No data yet and not done — sleep until signaled
            [state->dataCondition lock];
            // Double-check condition to avoid spurious wakeup issues
            if (state->queue->is_empty() && !state->synthesisDone.load(std::memory_order_acquire)) {
                [state->dataCondition wait];
            }
            [state->dataCondition unlock];
        }
    }

    delete state->queue;
    delete state;
}

- (void)cancel {
    if (tls_engineState) {
        tls_engineState->cancelled.store(true, std::memory_order_release);
    }
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
