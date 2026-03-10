//
//  RHVoiceEngine.mm
//  Ukrainian Voices Extension
//
//  РЕАЛЬНИЙ RHVoice синтез!
//

#import "RHVoiceEngine.h"
#include "RHVoice.h"
#import <AVFoundation/AVFoundation.h>

static NSMutableData *audioBuffer = nil;
static int currentSampleRate = 0;

// Callbacks для RHVoice
static int set_sample_rate_callback(int sample_rate, void* user_data) {
    currentSampleRate = sample_rate;
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    if (!audioBuffer) {
        audioBuffer = [[NSMutableData alloc] init];
    }
    [audioBuffer appendBytes:samples length:count * sizeof(short)];
    return 1;
}

@interface RHVoiceEngine ()
@property (assign) RHVoice_tts_engine engine;
@property (assign) BOOL initialized;
@end

@implementation RHVoiceEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        self.initialized = NO;
        self.engine = NULL;
        [self initializeEngine];
    }
    return self;
}

- (BOOL)initializeEngine {
    if (self.initialized) {
        return YES;
    }
    
    // ВИПРАВЛЕНО: Правильний шлях до голосів
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *resourcePath = [bundle resourcePath];
    NSString *voicesPath = [resourcePath stringByAppendingPathComponent:@"Voices"];
    
    NSLog(@"🔍 Looking for voices at: %@", voicesPath);
    
    // Перевіряємо чи існує папка
    BOOL isDirectory;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:voicesPath isDirectory:&isDirectory];
    
    if (!exists || !isDirectory) {
        NSLog(@"❌ Voices directory not found at: %@", voicesPath);
        // Спробуємо альтернативний шлях
        voicesPath = [bundle pathForResource:@"Voices" ofType:nil];
        if (!voicesPath) {
            NSLog(@"❌ Voices path not found!");
            return NO;
        }
        NSLog(@"✅ Found voices at alternative path: %@", voicesPath);
    } else {
        NSLog(@"✅ Found voices directory");
    }
    
    RHVoice_init_params params;
    memset(&params, 0, sizeof(params));
    params.data_path = [voicesPath UTF8String];
    params.config_path = [voicesPath UTF8String];
    params.resource_paths = NULL;
    params.options = 0;
    
    RHVoice_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;
    params.callbacks = callbacks;
    
    self.engine = RHVoice_new_tts_engine(&params);
    
    if (!self.engine) {
        NSLog(@"❌ Failed to create RHVoice engine");
        return NO;
    }
    
    self.initialized = YES;
    NSLog(@"✅ RHVoice engine initialized!");
    return YES;
}

- (AVAudioPCMBuffer *)synthesize:(NSString *)text
                           voice:(NSString *)voiceName
                            rate:(double)rate
                          volume:(double)volume
                           pitch:(double)pitch {
    
    if (!self.initialized || !text || [text length] == 0) {
        return nil;
    }
    
    // Очищаємо буфер
    audioBuffer = nil;
    currentSampleRate = 0;
    
    // Налаштовуємо параметри
    RHVoice_synth_params synth_params;
    memset(&synth_params, 0, sizeof(synth_params));
    synth_params.voice_profile = [voiceName UTF8String];
    synth_params.absolute_rate = (rate - 1.0);
    synth_params.relative_rate = rate;
    synth_params.absolute_pitch = (pitch - 1.0);
    synth_params.relative_pitch = pitch;
    synth_params.relative_volume = volume;
    
    // Синтезуємо
    const char *textCStr = [text UTF8String];
    RHVoice_message message = RHVoice_new_message(
        self.engine,
        textCStr,
        strlen(textCStr),
        RHVoice_message_text,
        &synth_params,
        NULL
    );
    
    if (!message) {
        NSLog(@"❌ Failed to create message");
        return nil;
    }
    
    int result = RHVoice_speak(message);
    RHVoice_delete_message(message);
    
    if (result == 0 || !audioBuffer || [audioBuffer length] == 0) {
        NSLog(@"❌ Synthesis failed");
        return nil;
    }
    
    // Конвертуємо в AVAudioPCMBuffer
    return [self convertToAudioBuffer:audioBuffer sampleRate:currentSampleRate];
}

- (AVAudioPCMBuffer *)convertToAudioBuffer:(NSData *)data sampleRate:(int)sampleRate {
    if (!data || [data length] == 0 || sampleRate == 0) {
        return nil;
    }
    
    AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:sampleRate
                                                               channels:1
                                                            interleaved:NO];
    
    if (!format) {
        return nil;
    }
    
    AVAudioFrameCount frameCount = (AVAudioFrameCount)([data length] / sizeof(short));
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                             frameCapacity:frameCount];
    
    if (!buffer) {
        return nil;
    }
    
    buffer.frameLength = frameCount;
    
    const short *samples = (const short *)[data bytes];
    float *channelData = buffer.floatChannelData[0];
    
    // Конвертуємо short → float
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
