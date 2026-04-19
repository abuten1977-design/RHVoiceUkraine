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
#include <memory>

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

struct AudioRequestState {
    ThreadSafeRingBuffer<void*, 2048> queue;
    std::atomic<size_t> queuedSamples{0};
    std::atomic<bool> completed{true};
    __strong NSData* currentChunk = nil;
    size_t currentChunkOffset = 0;

    ~AudioRequestState() {
        if (currentChunk) {
            currentChunk = nil;
        }

        void* chunkPtr = nullptr;
        while (queue.pop(chunkPtr)) {
            if (chunkPtr) {
                CFBridgingRelease(chunkPtr);
            }
        }
    }
};

// MARK: - Thread-local pointer to current EngineState

static __thread EngineState* tls_engineState = nullptr;
static constexpr NSTimeInterval kCancelWaitTimeoutSec = 1.5;

@interface RHVoiceAudioRequestToken () {
@public
    std::shared_ptr<AudioRequestState> _state;
}
@end

@implementation RHVoiceAudioRequestToken
@end

@interface RHVoiceAudioBuffer () {
@private
    std::shared_ptr<AudioRequestState> _activeState;
}
@end

@implementation RHVoiceAudioBuffer

- (instancetype)init {
    self = [super init];
    if (self) {
        auto state = std::make_shared<AudioRequestState>();
        std::atomic_store(&_activeState, state);
    }
    return self;
}

- (RHVoiceAudioRequestToken *)beginRequest {
    auto state = std::make_shared<AudioRequestState>();
    state->completed.store(false, std::memory_order_release);
    std::atomic_store(&_activeState, state);

    RHVoiceAudioRequestToken* token = [RHVoiceAudioRequestToken new];
    token->_state = state;
    return token;
}

- (void)cancelCurrentRequest {
    auto state = std::make_shared<AudioRequestState>();
    state->completed.store(true, std::memory_order_release);
    std::atomic_store(&_activeState, state);
}

- (BOOL)appendSamples:(const short *)samples
                count:(unsigned int)count
                token:(RHVoiceAudioRequestToken *)token {
    if (!samples || count == 0 || !token) return NO;

    auto tokenState = token->_state;
    auto activeState = std::atomic_load(&_activeState);
    if (!tokenState || tokenState.get() != activeState.get()) return NO;
    if (tokenState->completed.load(std::memory_order_acquire)) return NO;

    NSData* chunk = [NSData dataWithBytes:samples length:count * sizeof(short)];
    void* retained = (__bridge_retained void*)chunk;
    if (!tokenState->queue.push(retained)) {
        CFBridgingRelease(retained);
        return NO;
    }

    tokenState->queuedSamples.fetch_add(count, std::memory_order_release);
    return YES;
}

- (void)markCompletedWithToken:(RHVoiceAudioRequestToken *)token {
    if (!token) return;
    auto tokenState = token->_state;
    if (!tokenState) return;
    tokenState->completed.store(true, std::memory_order_release);
}

- (NSUInteger)availableFrames {
    auto state = std::atomic_load(&_activeState);
    if (!state) return 0;
    return state->queuedSamples.load(std::memory_order_acquire);
}

- (NSUInteger)readFrames:(float *)destination maxFrames:(NSUInteger)maxFrames {
    if (!destination || maxFrames == 0) return 0;

    auto state = std::atomic_load(&_activeState);
    if (!state) return 0;

    size_t copied = 0;
    while (copied < maxFrames) {
        if (!state->currentChunk || state->currentChunkOffset >= state->currentChunk.length / sizeof(short)) {
            if (state->currentChunk) {
                state->currentChunk = nil;
                state->currentChunkOffset = 0;
            }

            void* chunkPtr = nullptr;
            if (!state->queue.pop(chunkPtr)) break;

            state->currentChunk = (__bridge_transfer NSData*)chunkPtr;
            state->currentChunkOffset = 0;
        }

        const short* samples = (const short*)state->currentChunk.bytes;
        const size_t totalSamples = state->currentChunk.length / sizeof(short);
        const size_t remaining = totalSamples - state->currentChunkOffset;
        const size_t toCopy = std::min(remaining, (size_t)(maxFrames - copied));
        for (size_t i = 0; i < toCopy; ++i) {
            destination[copied + i] = samples[state->currentChunkOffset + i] / 32768.0f;
        }

        state->currentChunkOffset += toCopy;
        state->queuedSamples.fetch_sub(toCopy, std::memory_order_acq_rel);
        copied += toCopy;
    }

    return copied;
}

- (BOOL)renderFrames:(float *)destination
           maxFrames:(NSUInteger)maxFrames
     preBufferFrames:(NSUInteger)preBufferFrames
         didComplete:(BOOL *)didComplete {
    if (didComplete) {
        *didComplete = NO;
    }
    if (!destination || maxFrames == 0) return NO;

    auto state = std::atomic_load(&_activeState);
    if (!state) {
        if (didComplete) {
            *didComplete = YES;
        }
        return NO;
    }

    const size_t available = state->queuedSamples.load(std::memory_order_acquire);
    const bool done = state->completed.load(std::memory_order_acquire);

    if (available == 0) {
        if (didComplete) {
            *didComplete = done;
        }
        return NO;
    }

    if (available < preBufferFrames && !done) {
        return NO;
    }

    size_t copied = 0;
    while (copied < maxFrames) {
        if (!state->currentChunk || state->currentChunkOffset >= state->currentChunk.length / sizeof(short)) {
            if (state->currentChunk) {
                state->currentChunk = nil;
                state->currentChunkOffset = 0;
            }

            void* chunkPtr = nullptr;
            if (!state->queue.pop(chunkPtr)) break;

            state->currentChunk = (__bridge_transfer NSData*)chunkPtr;
            state->currentChunkOffset = 0;
        }

        const short* samples = (const short*)state->currentChunk.bytes;
        const size_t totalSamples = state->currentChunk.length / sizeof(short);
        const size_t remaining = totalSamples - state->currentChunkOffset;
        const size_t toCopy = std::min(remaining, (size_t)(maxFrames - copied));
        for (size_t i = 0; i < toCopy; ++i) {
            destination[copied + i] = samples[state->currentChunkOffset + i] / 32768.0f;
        }

        state->currentChunkOffset += toCopy;
        state->queuedSamples.fetch_sub(toCopy, std::memory_order_acq_rel);
        copied += toCopy;
    }

    bool playbackComplete = false;
    if (state->queuedSamples.load(std::memory_order_acquire) == 0) {
        const bool chunkExhausted = (!state->currentChunk ||
            state->currentChunkOffset >= state->currentChunk.length / sizeof(short));
        playbackComplete = chunkExhausted && state->completed.load(std::memory_order_acquire);
    }

    if (didComplete) {
        *didComplete = playbackComplete;
    }
    return copied > 0;
}

- (BOOL)isPlaybackComplete {
    auto state = std::atomic_load(&_activeState);
    if (!state) return YES;

    if (state->queuedSamples.load(std::memory_order_acquire) > 0) return NO;
    if (state->currentChunk && state->currentChunkOffset < state->currentChunk.length / sizeof(short)) {
        return NO;
    }

    return state->completed.load(std::memory_order_acquire);
}

@end

// MARK: - C Callbacks

static int set_sample_rate_callback(int sample_rate, void* user_data) {
    EngineState* state = static_cast<EngineState*>(user_data);
    if (state) {
        state->sampleRate.store(sample_rate, std::memory_order_release);
    }
    // Also update TLS if available
    if (tls_engineState) {
        tls_engineState->sampleRate.store(sample_rate, std::memory_order_release);
    }
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    NSLog(@"🔊 play_speech_callback: count=%u user_data=%p tls=%p", count, user_data, tls_engineState);
    // Prefer user_data over TLS — works across threads
    EngineState* state = static_cast<EngineState*>(user_data);
    if (!state) state = tls_engineState;
    if (!state) return 1;
    if (state->cancelled.load(std::memory_order_acquire)) return 0;

    NSData* chunk = [NSData dataWithBytes:samples length:count * sizeof(short)];
    void* retained = (__bridge_retained void*)chunk;

    if (state->dataCondition) {
        [state->dataCondition lock];
        if (!state->queue->push(retained)) {
            [state->dataCondition unlock];
            CFBridgingRelease(retained);
            return 1;
        }
        [state->dataCondition signal];
        [state->dataCondition unlock];
    } else {
        if (!state->queue->push(retained)) {
            CFBridgingRelease(retained);
        }
    }
    return 1;
}

// MARK: - @interface

@interface RHVoiceEngine ()
@property (assign) RHVoice_tts_engine engine;
@property (assign) BOOL initialized;
@property (strong) NSCondition* activeStateCondition;
@property (assign) EngineState* activeStreamingState;
@end

// MARK: - @implementation

@implementation RHVoiceEngine

+ (NSDictionary<NSString *, NSString *> *)voiceProfileAliases {
    static NSDictionary<NSString *, NSString *> *aliases;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        aliases = @{
            @"anatol": @"Anatol",
            @"marianna": @"Marianna",
            @"natalia": @"Natalia",
            @"volodymyr": @"Volodymyr"
        };
    });
    return aliases;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        _engine = NULL;
        _activeStateCondition = [[NSCondition alloc] init];
        [self initializeEngine];
    }
    return self;
}

- (BOOL)initializeEngine {
    if (self.initialized) return YES;

    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDir = NO;

    // Try RHVoiceData first (contains both languages/ and voices/ subdirs)
    NSString* dataPath = [[bundle resourcePath] stringByAppendingPathComponent:@"RHVoiceData"];
    if (![fm fileExistsAtPath:dataPath isDirectory:&isDir] || !isDir) {
        dataPath = [bundle pathForResource:@"RHVoiceData" ofType:nil];
    }

    // Fallback: legacy Voices-only path (won't have language data, but try anyway)
    if (!dataPath) {
        dataPath = [[bundle resourcePath] stringByAppendingPathComponent:@"Voices"];
        if (![fm fileExistsAtPath:dataPath isDirectory:&isDir] || !isDir) {
            dataPath = [bundle pathForResource:@"Voices" ofType:nil];
        }
    }

    if (!dataPath) {
        return NO;
    }

    RHVoice_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;

    RHVoice_init_params params;
    memset(&params, 0, sizeof(params));
    params.data_path = [dataPath UTF8String];
    params.config_path = NULL;
    params.callbacks = callbacks;

    self.engine = RHVoice_new_tts_engine(&params);
    if (!self.engine) { return NO; }

    // Verify voices loaded
    unsigned int nVoices = RHVoice_get_number_of_voices(self.engine);
    unsigned int nProfiles = RHVoice_get_number_of_voice_profiles(self.engine);
    (void)nVoices;
    (void)nProfiles;

    self.initialized = YES;
    return YES;
}

- (RHVoice_message)buildMessage:(NSString*)text voice:(NSString*)voice
                           rate:(double)rate volume:(double)volume pitch:(double)pitch
                          state:(EngineState*)state {
    NSString* alias = [[self class] voiceProfileAliases][voice.lowercaseString];
    NSString* normalizedVoice = alias ? alias : voice;

    RHVoice_synth_params p;
    memset(&p, 0, sizeof(p));
    p.voice_profile = [normalizedVoice UTF8String];
    double mappedRate = rate > 0 ? rate * 2.0 : 1.0;
    p.absolute_rate = 0.0;
    p.relative_rate = mappedRate;
    p.absolute_pitch = 0.0;
    p.relative_pitch = pitch > 0 ? pitch : 1.0;
    p.relative_volume = volume > 0 ? volume : 1.0;

    const char* t = [text UTF8String];
    NSLog(@"🎙️ buildMessage voice='%@' normalized='%@' rate=%.2f→%.2f textLength=%lu",
          voice, normalizedVoice, rate, mappedRate, (unsigned long)text.length);
    RHVoice_message msg = RHVoice_new_message(self.engine, t, (unsigned int)strlen(t),
                               RHVoice_message_text, &p,
                               (void*)state);  // Pass EngineState as user_data
    if (!msg) {
        NSLog(@"❌ RHVoice_new_message returned NULL for voice='%@'", normalizedVoice);
    }
    return msg;
}

- (void)publishActiveState:(EngineState*)state {
    [self.activeStateCondition lock];
    self.activeStreamingState = state;
    [self.activeStateCondition broadcast];
    [self.activeStateCondition unlock];
}

- (void)clearActiveStateIfMatches:(EngineState*)state {
    [self.activeStateCondition lock];
    if (self.activeStreamingState == state) {
        self.activeStreamingState = nullptr;
        [self.activeStateCondition broadcast];
    }
    [self.activeStateCondition unlock];
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

    RHVoice_message msg = [self buildMessage:text voice:voice rate:rate volume:volume pitch:pitch state:&state];
    if (!msg) {
        NSLog(@"❌ buildMessage failed for voice '%@'", voice);
        tls_engineState = nullptr;
        return nil;
    }

    NSLog(@"▶️ RHVoice_speak begin voice='%@'", voice);
    RHVoice_speak(msg);
    NSLog(@"⏹️ RHVoice_speak end voice='%@'", voice);
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

    // NOTE: Do NOT call [self cancel] here — the caller (Swift) already called
    // audioBuffer.beginRequest() which set up the active state. Calling cancel()
    // would replace _activeState with a new empty state, causing render block
    // to never receive data.

    // Heap-allocated — lifetime spans both producer and consumer
    EngineState* state = new (std::nothrow) EngineState();
    if (!state) {
        NSLog(@"❌ synthesizeStreaming failed: EngineState allocation failed");
        return;
    }

    state->queue = new (std::nothrow) ThreadSafeRingBuffer<void*>();
    if (!state->queue) {
        NSLog(@"❌ synthesizeStreaming failed: queue allocation failed");
        delete state;
        return;
    }
    state->cancelled.store(false, std::memory_order_release);
    state->sampleRate.store(24000, std::memory_order_release);
    state->synthesisDone.store(false, std::memory_order_release);
    state->dataCondition = [[NSCondition alloc] init];
    if (!state->dataCondition) {
        NSLog(@"❌ synthesizeStreaming failed: NSCondition allocation failed");
        delete state->queue;
        delete state;
        return;
    }
    [self publishActiveState:state];

    NSString* textCopy = [text copy];
    NSString* voiceCopy = [voice copy];
    RHVoiceEngine* __weak weakSelf = self;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RHVoiceEngine* strongSelf = weakSelf;
        // TLS set in THIS thread — callbacks fire synchronously from RHVoice_speak here
        tls_engineState = state;

        RHVoice_message msg = nullptr;
        if (strongSelf) {
            msg = [strongSelf buildMessage:textCopy voice:voiceCopy
                                      rate:rate volume:volume pitch:pitch state:state];
        }
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
        if (strongSelf) {
            [strongSelf clearActiveStateIfMatches:state];
        }
    });

    // Consumer loop — sleeps on NSCondition until data arrives or synthesis done
    while (true) {
        void* chunkPtr = nullptr;
        if (state->queue->pop(chunkPtr)) {
            NSData* chunk = (__bridge_transfer NSData*)chunkPtr;
            if (!state->cancelled.load(std::memory_order_acquire)) {
                const short* samples = (const short*)chunk.bytes;
                unsigned int count = (unsigned int)(chunk.length / sizeof(short));
                int sr = state->sampleRate.load(std::memory_order_acquire);
                if (sr <= 0) sr = 24000;
                chunkCallback(samples, count, sr);
            }
        } else if (state->synthesisDone.load(std::memory_order_acquire)) {
            // Drain any remaining chunks after done signal
            while (state->queue->pop(chunkPtr)) {
                if (chunkPtr) {
                    NSData* chunk = (__bridge_transfer NSData*)chunkPtr;
                    if (!state->cancelled.load(std::memory_order_acquire)) {
                        const short* samples = (const short*)chunk.bytes;
                        unsigned int count = (unsigned int)(chunk.length / sizeof(short));
                        int sr = state->sampleRate.load(std::memory_order_acquire);
                        if (sr <= 0) sr = 24000;
                        chunkCallback(samples, count, sr);
                    }
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
    [self.activeStateCondition lock];
    EngineState* state = self.activeStreamingState;
    if (!state) {
        [self.activeStateCondition unlock];
        return;
    }

    state->cancelled.store(true, std::memory_order_release);
    [state->dataCondition lock];
    [state->dataCondition broadcast];
    [state->dataCondition unlock];

    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:kCancelWaitTimeoutSec];
    while (self.activeStreamingState == state) {
        if (![self.activeStateCondition waitUntilDate:deadline]) {
            NSLog(@"⚠️ cancel timeout after %.1f sec; continuing without blocking caller", kCancelWaitTimeoutSec);
            break;
        }
    }
    [self.activeStateCondition unlock];
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
