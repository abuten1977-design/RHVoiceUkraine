#import <Foundation/Foundation.h>
#import "RHVoiceWrapper.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Starting RHVoice test...");
        
        // Initialize RHVoice
        NSLog(@"Initializing RHVoice...");
        [RHVoiceWrapper initializeRHVoice];
        
        // Test synthesis
        NSString *testText = @"Привіт! Це тест українського синтезу мовлення.";
        NSLog(@"Synthesizing text: %@", testText);
        
        NSData *audioData = [RHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
        
        if (audioData && audioData.length > 0) {
            NSLog(@"✅ SUCCESS! Generated audio data: %lu bytes", (unsigned long)audioData.length);
            
            // Save to file
            NSString *outputPath = @"/Users/admin/RHVoiceUkraine/test_output.wav";
            
            // Create simple WAV header
            NSMutableData *wavData = [NSMutableData data];
            
            // WAV header
            int dataSize = (int)audioData.length;
            int fileSize = dataSize + 44 - 8;
            int sampleRate = 22050;
            short audioFormat = 1; // PCM
            short numChannels = 1; // Mono
            int byteRate = sampleRate * numChannels * 2; // 16-bit
            short blockAlign = numChannels * 2;
            short bitsPerSample = 16;
            
            [wavData appendBytes:"RIFF" length:4];
            [wavData appendBytes:&fileSize length:4];
            [wavData appendBytes:"WAVE" length:4];
            [wavData appendBytes:"fmt " length:4];
            
            int fmtSize = 16;
            [wavData appendBytes:&fmtSize length:4];
            [wavData appendBytes:&audioFormat length:2];
            [wavData appendBytes:&numChannels length:2];
            [wavData appendBytes:&sampleRate length:4];
            [wavData appendBytes:&byteRate length:4];
            [wavData appendBytes:&blockAlign length:2];
            [wavData appendBytes:&bitsPerSample length:2];
            [wavData appendBytes:"data" length:4];
            [wavData appendBytes:&dataSize length:4];
            
            // Append PCM data
            [wavData appendData:audioData];
            
            if ([wavData writeToFile:outputPath atomically:YES]) {
                NSLog(@"✅ Audio saved to: %@", outputPath);
                NSLog(@"WAV file size: %lu bytes", (unsigned long)wavData.length);
            } else {
                NSLog(@"❌ Failed to save audio file");
            }
        } else {
            NSLog(@"❌ FAILED! No audio data generated");
        }
        
        NSLog(@"Test completed.");
    }
    return 0;
}
