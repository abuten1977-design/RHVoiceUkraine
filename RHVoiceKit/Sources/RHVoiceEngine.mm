//
//  RHVoiceEngine.mm
//  Ukrainian Voices Extension
//

#import "RHVoiceEngine.h"
#include "RHVoice.h"
#import <AVFoundation/AVFoundation.h>
#import <os/log.h>
#import <TargetConditionals.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <memory>
#include "RHVoiceDebugLog.h"

// MARK: - ThreadSafeRingBuffer
// Internal SPSC queue used by the Stage 4 hybrid model:
// producer writes retained PCM chunks, consumer reads them as frames.

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
    ThreadSafeRingBuffer<void*>* queue = nullptr;
    std::atomic<bool> cancelled{false};
    std::atomic<int> sampleRate{24000};
    std::atomic<bool> synthesisDone{false};
    NSCondition* dataCondition = nil;

    bool ownsQueue = false; // true only when queue is heap-allocated

    ~EngineState() {
        // Drain and release any remaining chunks
        if (queue) {
            void* chunkPtr = nullptr;
            while (queue->pop(chunkPtr)) {
                if (chunkPtr) CFBridgingRelease(chunkPtr);
            }
            if (ownsQueue) delete queue;
        }
    }
};

// MARK: - Thread-local pointer to current EngineState

static __thread EngineState* tls_engineState = nullptr;

static NSString* RHVoiceResolveDataPath(Class engineClass, NSBundle** resolvedBundle) {
    NSArray<NSBundle*>* candidateBundles = @[
        [NSBundle mainBundle],
        [NSBundle bundleForClass:engineClass]
    ];
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDir = NO;

    for (NSBundle* bundle in candidateBundles) {
        NSArray<NSString*>* resourceNames = @[@"RHVoiceData", @"Voices"];
        for (NSString* resourceName in resourceNames) {
            NSString* candidate = [[bundle resourcePath] stringByAppendingPathComponent:resourceName];
            if ([fm fileExistsAtPath:candidate isDirectory:&isDir] && isDir) {
                if (resolvedBundle) *resolvedBundle = bundle;
                return candidate;
            }

            candidate = [bundle pathForResource:resourceName ofType:nil];
            if (candidate && [fm fileExistsAtPath:candidate isDirectory:&isDir] && isDir) {
                if (resolvedBundle) *resolvedBundle = bundle;
                return candidate;
            }
        }
    }

    return nil;
}

#if TARGET_OS_OSX
static NSString* const RHVoiceAppGroupIdentifier = @"5NNZPP8CRR.group.rhvoice.UkrainianVoices.shared";
#else
static NSString* const RHVoiceAppGroupIdentifier = @"group.rhvoice.UkrainianVoices.shared";
#endif
static NSString* const RHVoicePersonalDictionaryFileName = @"user_dictionary.txt";

static NSURL* RHVoiceSharedContainerURL(void) {
    return [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:RHVoiceAppGroupIdentifier];
}

static NSString* RHVoicePersonalDictionarySignature(void) {
    NSURL* containerURL = RHVoiceSharedContainerURL();
    if (!containerURL) return @"no-app-group";

    NSString* path = [[containerURL URLByAppendingPathComponent:RHVoicePersonalDictionaryFileName] path];
    NSDictionary<NSFileAttributeKey, id>* attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attributes) return @"missing";

    NSDate* modified = attributes[NSFileModificationDate];
    NSNumber* size = attributes[NSFileSize];
    return [NSString stringWithFormat:@"%lld:%llu",
            (long long)modified.timeIntervalSince1970,
            size.unsignedLongLongValue];
}

static NSString* RHVoicePrepareWritableConfigPath(NSString* dataPath) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* containerURL = RHVoiceSharedContainerURL();
    if (!containerURL) return dataPath;

    NSURL* configURL = [containerURL URLByAppendingPathComponent:@"RHVoiceConfig" isDirectory:YES];
    NSURL* dictURL = [[configURL URLByAppendingPathComponent:@"dicts" isDirectory:YES]
        URLByAppendingPathComponent:@"Ukrainian" isDirectory:YES];
    NSError* error = nil;
    if (![fm createDirectoryAtURL:dictURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        RHVoiceDebugLogWrite("USERDICT personal config mkdir failed: %s", error.localizedDescription.UTF8String);
        return dataPath;
    }

    NSString* sourceConfig = [dataPath stringByAppendingPathComponent:@"RHVoice.conf"];
    NSString* targetConfig = [[configURL URLByAppendingPathComponent:@"RHVoice.conf"] path];
    if ([fm fileExistsAtPath:sourceConfig]) {
        [fm removeItemAtPath:targetConfig error:nil];
        if (![fm copyItemAtPath:sourceConfig toPath:targetConfig error:&error]) {
            RHVoiceDebugLogWrite("USERDICT config copy failed: %s", error.localizedDescription.UTF8String);
            return dataPath;
        }
    }

    NSString* personalSource = [[[containerURL URLByAppendingPathComponent:RHVoicePersonalDictionaryFileName] standardizedURL] path];
    NSString* personalTarget = [[dictURL URLByAppendingPathComponent:RHVoicePersonalDictionaryFileName] path];
    [fm removeItemAtPath:personalTarget error:nil];
    if ([fm fileExistsAtPath:personalSource]) {
        if (![fm copyItemAtPath:personalSource toPath:personalTarget error:&error]) {
            RHVoiceDebugLogWrite("USERDICT personal copy failed: %s", error.localizedDescription.UTF8String);
            return dataPath;
        }
        RHVoiceDebugLogWrite("USERDICT personal loaded path=%s", personalSource.UTF8String);
    } else {
        RHVoiceDebugLogWrite("USERDICT personal missing; bundled only");
    }

    return [configURL path];
}

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
@property (copy) NSString* personalDictionarySignature;
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
        _personalDictionarySignature = @"";
        [self initializeEngine];
    }
    return self;
}

- (void)refreshPersonalDictionaryIfNeeded {
    NSString* signature = RHVoicePersonalDictionarySignature();
    if (!self.initialized || [signature isEqualToString:self.personalDictionarySignature]) {
        return;
    }

    RHVoiceDebugLogWrite("USERDICT personal changed old=%s new=%s",
                         self.personalDictionarySignature.UTF8String,
                         signature.UTF8String);
    [self cancel];
    if (self.engine) {
        RHVoice_delete_tts_engine(self.engine);
        self.engine = NULL;
    }
    self.initialized = NO;
    [self initializeEngine];
}

- (BOOL)initializeEngine {
    if (self.initialized) return YES;

    NSFileManager* fm = [NSFileManager defaultManager];
    NSBundle* resolvedBundle = nil;
    NSString* dataPath = RHVoiceResolveDataPath([self class], &resolvedBundle);

    if (!dataPath) {
        NSLog(@"❌ RHVoiceData not found in app/framework bundles. main=%@ framework=%@",
              [NSBundle mainBundle].resourcePath,
              [NSBundle bundleForClass:[self class]].resourcePath);
        return NO;
    }

    NSLog(@"✅ RHVoice data path: %@ (bundle=%@)", dataPath, resolvedBundle.resourcePath);
    NSLog(@"✅ Contents: %@", [fm contentsOfDirectoryAtPath:dataPath error:nil]);
    
    // Check permissions
    BOOL isReadable = [fm isReadableFileAtPath:dataPath];
    NSLog(@"ℹ️ Data path is readable: %d", isReadable);

    RHVoice_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;

    NSString* configPath = RHVoicePrepareWritableConfigPath(dataPath);
    self.personalDictionarySignature = RHVoicePersonalDictionarySignature();
    NSLog(@"✅ RHVoice config path: %@", configPath);
    RHVoiceDebugLogWrite("USERDICT config path=%s signature=%s",
                         configPath.UTF8String,
                         self.personalDictionarySignature.UTF8String);

    RHVoice_init_params params;
    memset(&params, 0, sizeof(params));
    params.data_path = [dataPath UTF8String];
    params.config_path = [configPath UTF8String];
    params.callbacks = callbacks;

    @try {
        self.engine = RHVoice_new_tts_engine(&params);
    } @catch (NSException *exception) {
        NSLog(@"❌ Engine threw NSException: %@ — %@", exception.name, exception.reason);
    }
    if (!self.engine) {
        NSLog(@"❌ Engine init failed for data_path: %@", dataPath);
        // Diagnostic: check subdirectories
        NSString* langPath = [dataPath stringByAppendingPathComponent:@"languages"];
        NSString* voicePath = [dataPath stringByAppendingPathComponent:@"voices"];
        NSLog(@"❌ languages/ exists: %d, contents: %@",
              [fm fileExistsAtPath:langPath],
              [fm contentsOfDirectoryAtPath:langPath error:nil]);
        NSLog(@"❌ voices/ exists: %d, contents: %@",
              [fm fileExistsAtPath:voicePath],
              [fm contentsOfDirectoryAtPath:voicePath error:nil]);
        NSString* ukPath = [langPath stringByAppendingPathComponent:@"Ukrainian"];
        NSLog(@"❌ Ukrainian/ exists: %d, contents: %@",
              [fm fileExistsAtPath:ukPath],
              [fm contentsOfDirectoryAtPath:ukPath error:nil]);
        NSString* anatol = [voicePath stringByAppendingPathComponent:@"anatol"];
        NSLog(@"❌ anatol/ exists: %d, contents: %@",
              [fm fileExistsAtPath:anatol],
              [fm contentsOfDirectoryAtPath:anatol error:nil]);
        return NO;
    }

    // Verify voices loaded
    unsigned int nVoices = RHVoice_get_number_of_voices(self.engine);
    unsigned int nProfiles = RHVoice_get_number_of_voice_profiles(self.engine);
    NSLog(@"✅ Engine ready: %u voices, %u profiles", nVoices, nProfiles);
    
    // Log available voice profiles.
    // IMPORTANT: Don't assume the returned list is NULL-terminated; use the reported count.
    // Otherwise we can walk past the end and crash inside NSLog("%s", ...).
    char const* const* profiles = RHVoice_get_voice_profiles(self.engine);
    if (profiles) {
        for (unsigned int i = 0; i < nProfiles; i++) {
            const char* name = profiles[i];
            if (name && name[0] != '\0') {
                NSLog(@"   Profile[%u]: %s", i, name);
            } else {
                NSLog(@"   Profile[%u]: (null)", i);
            }
        }
    }

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

    // Detect SSML: VoiceOver sends rate/pitch/volume via SSML prosody tags
    BOOL isSSML = [text containsString:@"<"];

    if (isSSML) {
        // Rate/volume extracted from SSML prosody, passed via parameters
        p.absolute_rate = 0.0;
        p.relative_rate = rate;
        p.flags = RHVoice_synth_flag_dont_clip_rate;
        p.absolute_pitch = 0.0;
        p.relative_pitch = pitch > 0 ? pitch : 1.0;
        p.relative_volume = volume > 0 ? volume : 1.0;
    } else {
        // For plain text (Preview): keep legacy multiplier without applying rate twice.
        double polishRate = fmax(0.5, rate * 2.0);
        double polishPitch = fmax(0.2, fmin(5.0, 0.5 + pitch * 0.5));
        p.absolute_rate = 0.0;
        p.relative_rate = polishRate;
        p.absolute_pitch = (polishPitch - 1.0);
        p.relative_pitch = polishPitch;
        p.relative_volume = volume > 0 ? volume : 1.0;
    }

    const char* t = [text UTF8String];
    NSString* textPreview = text.length > 300 ? [text substringToIndex:300] : text;
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO, "[RHVOICE_TIMING] buildMessage textLength=%{public}lu", (unsigned long)text.length);
    RHVoiceDebugLogWrite("buildMessage text: %s", [textPreview UTF8String]);
    NSLog(@"🎙️ buildMessage voice='%@' rate=%.2f→abs=%.2f/rel=%.2f pitch=%.2f→abs=%.2f/rel=%.2f vol=%.2f isSSML=%d",
          normalizedVoice, rate, p.absolute_rate, p.relative_rate,
          pitch, p.absolute_pitch, p.relative_pitch, p.relative_volume, isSSML);
    RHVoiceDebugLogWrite("buildMessage voice=%s rate=%.2f->abs=%.2f/rel=%.2f pitch=%.2f->abs=%.2f/rel=%.2f vol=%.2f isSSML=%d",
          [normalizedVoice UTF8String], rate, p.absolute_rate, p.relative_rate,
          pitch, p.absolute_pitch, p.relative_pitch, p.relative_volume, isSSML);

    RHVoice_message_type msgType = isSSML ? RHVoice_message_ssml : RHVoice_message_text;

    RHVoice_message msg = RHVoice_new_message(self.engine, t, (unsigned int)strlen(t),
                               msgType, &p,
                               (void*)state);  // Pass EngineState as user_data
    if (!msg) {
        NSLog(@"❌ RHVoice_new_message returned NULL for voice='%@'", normalizedVoice);
    }
    return msg;
}

- (RHVoice_message)buildDefaultMessage:(NSString*)text state:(EngineState*)state {
    const char* t = [text UTF8String];
    RHVoice_message_type msgType = [text containsString:@"<"] ? RHVoice_message_ssml : RHVoice_message_text;
    return RHVoice_new_message(self.engine,
                               t,
                               (unsigned int)strlen(t),
                               msgType,
                               NULL,
                               (void*)state);
}

// MARK: - Sync synthesize (для preview в App)

- (nullable AVAudioPCMBuffer*)synthesize:(NSString*)text voice:(NSString*)voice
                                    rate:(double)rate volume:(double)volume pitch:(double)pitch {
    NSLog(@"🔍 synthesize called: initialized=%d, text='%@', voice='%@'", self.initialized, text, voice);
    [self refreshPersonalDictionaryIfNeeded];
    
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

    int speakResult = RHVoice_speak(msg);
    RHVoice_delete_message(msg);

    if (speakResult == 0) {
        NSLog(@"❌ RHVoice_speak returned 0 for voice '%@', retrying with default profile", voice);
        RHVoice_message fallbackMsg = [self buildDefaultMessage:text state:&state];
        if (fallbackMsg) {
            speakResult = RHVoice_speak(fallbackMsg);
            RHVoice_delete_message(fallbackMsg);
            NSLog(@"ℹ️ Fallback RHVoice_speak result=%d sampleRate=%d", speakResult,
                  state.sampleRate.load(std::memory_order_acquire));
        } else {
            NSLog(@"❌ Failed to create fallback RHVoice message");
        }
    } else {
        NSLog(@"ℹ️ RHVoice_speak result=%d sampleRate=%d", speakResult,
              state.sampleRate.load(std::memory_order_acquire));
    }

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

- (void)cancel {
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [self.activeStateCondition lock];
    EngineState* state = self.activeStreamingState;
    if (!state) {
        [self.activeStateCondition unlock];
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO, "[RHVOICE_TIMING] cancel: no active state (%{public}.1f ms)", (CFAbsoluteTimeGetCurrent()-t0)*1000);
        RHVoiceDebugLogWrite("cancel: no active state (%.1f ms)", (CFAbsoluteTimeGetCurrent()-t0)*1000);
        return;
    }

    // Non-blocking: set flag and wake consumer, don't wait
    state->cancelled.store(true, std::memory_order_release);
    if (state->dataCondition) {
        [state->dataCondition lock];
        [state->dataCondition broadcast];
        [state->dataCondition unlock];
    }
    [self.activeStateCondition unlock];
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO, "[RHVOICE_TIMING] cancel: flagged in %{public}.1f ms", (CFAbsoluteTimeGetCurrent()-t0)*1000);
    RHVoiceDebugLogWrite("cancel: flagged in %.1f ms", (CFAbsoluteTimeGetCurrent()-t0)*1000);
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
