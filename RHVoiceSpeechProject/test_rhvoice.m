#import <Foundation/Foundation.h>
#import "RHVoiceEngine/include/RHVoiceWrapper.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Starting RHVoice test...");
        
        [RHVoiceWrapper initializeRHVoice];
        NSLog(@"RHVoice initialized");
        
        NSString *testText = @"Привіт! Це тест українського голосу.";
        NSLog(@"Testing text: %@", testText);
        
        NSData *audioData = [RHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
        if (audioData) {
            NSLog(@"Audio synthesis successful! Generated %lu bytes", (unsigned long)[audioData length]);
            
            // Save to file
            NSString *outputPath = @"/tmp/test_output.wav";
            BOOL success = [audioData writeToFile:outputPath atomically:YES];
            NSLog(@"Audio saved to %@: %@", outputPath, success ? @"SUCCESS" : @"FAILED");
        } else {
            NSLog(@"Audio synthesis failed!");
        }
    }
    return 0;
}
