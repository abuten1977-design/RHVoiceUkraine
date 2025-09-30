#import <Foundation/Foundation.h>
#import "RHVoiceWrapper.h"
#include "RHVoice.h" // Include the C API header
#include <vector>
#include <string>

// Static variables to store audio data, sample rate, and TTS engine handle
static NSMutableData* g_audioData = nil;
static uint32_t g_sampleRate = 0;
static RHVoice_tts_engine g_ttsEngine = NULL;

// Static C-style callback function for RHVoice audio output
static int rhvoice_play_speech_callback(const short *samples, unsigned int count, void* user_data) {
    if (samples && count > 0) {
        NSMutableData* audioData = (__bridge NSMutableData*)user_data;
        [audioData appendBytes:samples length:count * sizeof(short)];
    }
    return 1; // Continue synthesis
}

// Static C-style callback function for RHVoice sample rate (optional, but good practice)
static int rhvoice_set_sample_rate_callback(int sample_rate, void* user_data) {
    g_sampleRate = sample_rate;
    NSLog(@"RHVoiceWrapper: Sample rate set to %u", g_sampleRate);
    return 1; // Success
}

@implementation RHVoiceWrapper

+ (void)initializeRHVoice {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Initialize g_audioData
        g_audioData = [[NSMutableData alloc] init];

        // Set data and config paths dynamically from the app bundle
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSString *dataPath = [bundle pathForResource:@"data" ofType:nil];
        NSString *configPath = [bundle pathForResource:@"config" ofType:nil];

        if (!dataPath) {
            NSLog(@"RHVoiceWrapper: Error - 'data' folder not found in bundle.");
            return;
        }
        if (!configPath) {
            NSLog(@"RHVoiceWrapper: Error - 'config' folder not found in bundle.");
            return;
        }

        // Convert NSString to C-style strings
        const char *cDataPath = [dataPath UTF8String];
        const char *cConfigPath = [configPath UTF8String];

        // Setup init parameters
        RHVoice_init_params init_params;
        memset(&init_params, 0, sizeof(RHVoice_init_params)); // Initialize to zeros
        init_params.data_path = cDataPath;
        init_params.config_path = cConfigPath;
        init_params.callbacks.play_speech = rhvoice_play_speech_callback;
        init_params.callbacks.set_sample_rate = rhvoice_set_sample_rate_callback;

        init_params.options = 0; // No special options for now

        // Initialize RHVoice engine
        g_ttsEngine = RHVoice_new_tts_engine(&init_params);

        if (g_ttsEngine == NULL) {
            NSLog(@"RHVoiceWrapper: Error initializing RHVoice engine.");
        } else {
            NSLog(@"RHVoiceWrapper: RHVoice engine initialized successfully.");
        }
    });
}

+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName {
    if (g_ttsEngine == NULL) {
        NSLog(@"RHVoiceWrapper: RHVoice engine not initialized.");
        return nil;
    }

    // Clear previous audio data
    [g_audioData setLength:0];

    // Convert NSString to C-style string
    const char *cText = [text UTF8String];

    // Setup synthesis parameters
    RHVoice_synth_params synth_params;
    memset(&synth_params, 0, sizeof(RHVoice_synth_params)); // Initialize to zeros
    synth_params.voice_profile = [voiceName UTF8String]; // Set the desired voice profile
    synth_params.absolute_rate = -1; // Use default
    synth_params.absolute_pitch = -1; // Use default
    synth_params.absolute_volume = -1; // Use default
    synth_params.relative_rate = 1; // Use default
    synth_params.relative_pitch = 1; // Use default
    synth_params.relative_volume = 1; // Use default
    synth_params.punctuation_mode = RHVoice_punctuation_default;
    synth_params.capitals_mode = RHVoice_capitals_default;
    synth_params.flags = 0;

    // Create RHVoice message
    RHVoice_message msg = RHVoice_new_message(g_ttsEngine, cText, strlen(cText), RHVoice_message_text, &synth_params, NULL);
    if (msg == NULL) {
        NSLog(@"RHVoiceWrapper: Failed to create RHVoice message.");
        return nil;
    }

    // Speak the message
    RHVoice_speak(msg);

    // Clean up message
    RHVoice_delete_message(msg);

    // Return accumulated audio data
    return g_audioData;
}

@end