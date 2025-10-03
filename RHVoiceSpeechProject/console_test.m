#import <Foundation/Foundation.h>
#import "RHVoiceEngine/include/RHVoiceWrapper.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Starting RHVoice console test...");
        
        // Initialize RHVoice
        [RHVoiceWrapper initializeRHVoice];
        NSLog(@"RHVoice initialized");
        
        // Test synthesis
        NSString *testText = @"Привіт! Це тест українського голосу.";
        NSLog(@"Testing text: %@", testText);
        
        NSData *audioData = [RHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
        if (audioData) {
            NSLog(@"Audio synthesis successful! Generated %lu bytes", (unsigned long)[audioData length]);
            
            // Save to file
            NSString *outputPath = @"/tmp/test_output.wav";
            BOOL success = [audioData writeToFile:outputPath atomically:YES];
            NSLog(@"Audio saved to %@: %@", outputPath, success ? @"SUCCESS" : @"FAILED");
            
            if (success) {
                NSLog(@"You can find the audio file at: %@", outputPath);
                NSLog(@"File size: %llu bytes", [[NSFileManager defaultManager] attributesOfItemAtPath:outputPath error:nil].fileSize);
            }
        } else {
            NSLog(@"Audio synthesis failed!");
        }
        
        NSLog(@"Test completed.");
    }
    return 0;
}
