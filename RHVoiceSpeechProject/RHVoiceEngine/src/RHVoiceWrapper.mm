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
    NSLog(@"RHVoiceWrapper: Audio callback - received %u samples", count);
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
        NSLog(@"RHVoiceWrapper: Starting initialization...");
        
        // Initialize g_audioData
        g_audioData = [[NSMutableData alloc] init];
        NSLog(@"RHVoiceWrapper: Audio data buffer initialized");

        // Set data and config paths dynamically from the app bundle
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSLog(@"RHVoiceWrapper: Bundle path: %@", bundle.bundlePath);
        
        // List bundle contents for debugging
        NSString *resourcesPath = [bundle.bundlePath stringByAppendingPathComponent:@"Resources"];
        NSError *error;
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:resourcesPath error:&error];
        if (contents) {
            NSLog(@"RHVoiceWrapper: Resources directory contents: %@", contents);
        } else {
            NSLog(@"RHVoiceWrapper: Error reading Resources directory: %@", error.localizedDescription);
        }
        
        // Look for RHVoiceModels instead of data
        NSString *dataPath = [bundle pathForResource:@"RHVoiceModels" ofType:nil];
        NSString *configPath = [bundle pathForResource:@"config" ofType:nil];

        NSLog(@"RHVoiceWrapper: Looking for RHVoiceModels at: %@", dataPath);
        NSLog(@"RHVoiceWrapper: Looking for config at: %@", configPath);

        if (!dataPath) {
            NSLog(@"RHVoiceWrapper: Error - 'RHVoiceModels' folder not found in bundle.");
            NSLog(@"RHVoiceWrapper: Available resources: %@", [bundle pathsForResourcesOfType:nil inDirectory:nil]);
            return;
        }
        if (!configPath) {
            NSLog(@"RHVoiceWrapper: Error - 'config' folder not found in bundle.");
            return;
        }

        // Convert NSString to C-style strings
        const char *cDataPath = [dataPath UTF8String];
        const char *cConfigPath = [configPath UTF8String];
        
        NSLog(@"RHVoiceWrapper: Using data path: %s", cDataPath);
        NSLog(@"RHVoiceWrapper: Using config path: %s", cConfigPath);

        // Setup init parameters
        RHVoice_init_params init_params;
        memset(&init_params, 0, sizeof(RHVoice_init_params)); // Initialize to zeros
        init_params.data_path = cDataPath;
        init_params.config_path = cConfigPath;
        init_params.callbacks.play_speech = rhvoice_play_speech_callback;
        init_params.callbacks.set_sample_rate = rhvoice_set_sample_rate_callback;

        init_params.options = 0; // No special options for now

        NSLog(@"RHVoiceWrapper: Calling RHVoice_new_tts_engine...");
        
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
    NSLog(@"RHVoiceWrapper: synthesizeText called with text: '%@', voice: '%@'", text, voiceName);
    
    if (g_ttsEngine == NULL) {
        NSLog(@"RHVoiceWrapper: RHVoice engine not initialized.");
        [self initializeRHVoice]; // Try to initialize
        if (g_ttsEngine == NULL) {
            NSLog(@"RHVoiceWrapper: Failed to initialize RHVoice engine.");
            return nil;
        }
    }

    // Clear previous audio data
    [g_audioData setLength:0];
    
    NSLog(@"RHVoiceWrapper: Starting synthesis...");

    // Convert text to C string
    const char *cText = [text UTF8String];
    unsigned int textLength = (unsigned int)strlen(cText);
    
    // Create synthesis parameters (can be NULL for defaults)
    RHVoice_synth_params *synth_params = NULL;
    
    // Create RHVoice message with correct parameters
    RHVoice_message message = RHVoice_new_message(
        g_ttsEngine,
        cText,
        textLength,
        RHVoice_message_text, // message type
        synth_params,         // synthesis parameters (NULL for defaults)
        (__bridge void*)g_audioData // user data for callback
    );
    
    if (message == NULL) {
        NSLog(@"RHVoiceWrapper: Failed to create RHVoice message.");
        return nil;
    }

    // Synthesize the message
    if (!RHVoice_speak(message)) {
        NSLog(@"RHVoiceWrapper: Failed to synthesize text.");
        RHVoice_delete_message(message);
        return nil;
    }

    NSLog(@"RHVoiceWrapper: Synthesis completed. Audio data length: %lu bytes", (unsigned long)g_audioData.length);

    // Clean up
    RHVoice_delete_message(message);

    // Return copy of audio data
    return [g_audioData copy];
}

@end
