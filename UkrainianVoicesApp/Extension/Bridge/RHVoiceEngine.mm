//
//  RHVoiceEngine.mm
//  Ukrainian Voices Extension
//

#import "RHVoiceEngine.h"
#include "RHVoice.h"
#import <AVFoundation/AVFoundation.h>

@interface RHVoiceEngine ()
@property (assign) RHVoice_tts_engine engine;
@property (assign) BOOL initialized;
@property (assign) int currentSampleRate;
@property (assign) BOOL cancelRequested;
@property (strong, nullable) NSMutableData *audioBuffer;
@property (copy, nullable) void(^chunkCallback)(const short* samples, unsigned int count, int sampleRate);
@end

// C callbacks — визначені після @interface щоб бачити properties
static int set_sample_rate_callback(int sample_rate, void* user_data) {
    if (!user_data) return 1;
    RHVoiceEngine *engine = (__bridge RHVoiceEngine*)user_data;
    engine.currentSampleRate = sample_rate;
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    if (!user_data) return 1;
    RHVoiceEngine *engine = (__bridge RHVoiceEngine*)user_data;
    if (engine.cancelRequested) return 0;
    if (engine.chunkCallback) {
        engine.chunkCallback(samples, count, engine.currentSampleRate);
    } else {
        [engine.audioBuffer appendBytes:samples length:count * sizeof(short)];
    }
    return 1;
}

@implementation RHVoiceEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        _engine = NULL;
        _currentSampleRate = 0;
        _cancelRequested = NO;
        _audioBuffer = nil;
        _chunkCallback = nil;
        [self initializeEngine];
    }
    return self;
}

- (BOOL)initializeEngine {
    if (self.initialized) return YES;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *resourcePath = [bundle resourcePath];
    NSString *voicesPath = [resourcePath stringByAppendingPathComponent:@"Voices"];

    BOOL isDirectory;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:voicesPath isDirectory:&isDirectory];

    if (!exists || !isDirectory) {
        voicesPath = [bundle pathForResource:@"Voices" ofType:nil];
        if (!voicesPath) {
            NSLog(@"❌ Voices path not found!");
            return NO;
        }
    }

    NSLog(@"✅ Voices path: %@", voicesPath);

    RHVoice_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;

    RHVoice_init_params params;
    memset(&params, 0, sizeof(params));
    params.data_path = [voicesPath UTF8String];
    params.config_path = [voicesPath UTF8String];
    params.resource_paths = NULL;
    params.options = 0;
    params.callbacks = callbacks;

    self.engine = RHVoice_new_tts_engine(&params);

    if (!self.engine) {
        NSLog(@"❌ Failed to create RHVoice engine");
        return NO;
    }

    self.initialized = YES;
    NSLog(@"✅ RHVoice engine initialized");
    return YES;
}

- (RHVoice_message)buildMessage:(NSString*)text
                          voice:(NSString*)voiceName
                           rate:(double)rate
                         volume:(double)volume
                          pitch:(double)pitch
                       userData:(void*)userData {
    RHVoice_synth_params synth_params;
    memset(&synth_params, 0, sizeof(synth_params));
    synth_params.voice_profile = [voiceName UTF8String];
    synth_params.absolute_rate = (rate - 1.0);
    synth_params.relative_rate = rate;
    synth_params.absolute_pitch = (pitch - 1.0);
    synth_params.relative_pitch = pitch;
    synth_params.relative_volume = volume;

    const char *textCStr = [text UTF8String];
    return RHVoice_new_message(
        self.engine,
        textCStr,
        (unsigned int)strlen(textCStr),
        RHVoice_message_text,
        &synth_params,
        userData
    );
}

- (nullable AVAudioPCMBuffer *)synthesize:(NSString *)text
                                    voice:(NSString *)voiceName
                                     rate:(double)rate
                                   volume:(double)volume
                                    pitch:(double)pitch {
    if (!self.initialized || !text || text.length == 0) return nil;

    self.cancelRequested = NO;
    self.chunkCallback = nil;
    self.audioBuffer = [[NSMutableData alloc] init];
    self.currentSampleRate = 0;

    RHVoice_message message = [self buildMessage:text voice:voiceName
                                            rate:rate volume:volume pitch:pitch
                                        userData:(__bridge void*)self];
    if (!message) return nil;

    RHVoice_speak(message);
    RHVoice_delete_message(message);

    NSMutableData *buffer = self.audioBuffer;
    int sampleRate = self.currentSampleRate;
    self.audioBuffer = nil;

    if (!buffer || buffer.length == 0 || sampleRate == 0) return nil;
    return [self convertToAudioBuffer:buffer sampleRate:sampleRate];
}

- (void)synthesizeStreaming:(NSString *)text
                     voice:(NSString *)voiceName
                      rate:(double)rate
                    volume:(double)volume
                     pitch:(double)pitch
                   onChunk:(void(^)(const short* samples, unsigned int count, int sampleRate))chunkCallback {
    if (!self.initialized || !text || text.length == 0) return;

    self.cancelRequested = NO;
    self.chunkCallback = chunkCallback;
    self.audioBuffer = nil;
    self.currentSampleRate = 0;

    RHVoice_message message = [self buildMessage:text voice:voiceName
                                            rate:rate volume:volume pitch:pitch
                                        userData:(__bridge void*)self];
    if (!message) {
        self.chunkCallback = nil;
        return;
    }

    RHVoice_speak(message);
    RHVoice_delete_message(message);
    self.chunkCallback = nil;
}

- (void)cancel {
    self.cancelRequested = YES;
}

- (AVAudioPCMBuffer *)convertToAudioBuffer:(NSData *)data sampleRate:(int)sampleRate {
    if (!data || data.length == 0 || sampleRate == 0) return nil;

    AVAudioFormat *format = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatFloat32
                  sampleRate:sampleRate
                    channels:1
                 interleaved:NO];
    if (!format) return nil;

    AVAudioFrameCount frameCount = (AVAudioFrameCount)(data.length / sizeof(short));
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]
        initWithPCMFormat:format frameCapacity:frameCount];
    if (!buffer) return nil;

    buffer.frameLength = frameCount;
    const short *samples = (const short *)data.bytes;
    float *channelData = buffer.floatChannelData[0];
    for (AVAudioFrameCount i = 0; i < frameCount; i++) {
        channelData[i] = samples[i] / 32768.0f;
    }
    return buffer;
}

- (void)dealloc {
    if (self.engine) {
        RHVoice_delete_tts_engine(self.engine);
        self.engine = NULL;
    }
}

@end
