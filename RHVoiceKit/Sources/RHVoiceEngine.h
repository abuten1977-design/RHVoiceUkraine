//
//  RHVoiceEngine.h
//  Ukrainian Voices Extension
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RHVoiceAudioRequestToken : NSObject
@end

@interface RHVoiceAudioBuffer : NSObject

- (instancetype)init;
- (RHVoiceAudioRequestToken *)beginRequest;
- (void)cancelCurrentRequest;
- (BOOL)appendSamples:(const short *)samples
                count:(unsigned int)count
                token:(RHVoiceAudioRequestToken *)token;
- (void)markCompletedWithToken:(RHVoiceAudioRequestToken *)token;
- (NSUInteger)availableFrames;
- (NSUInteger)readFrames:(float *)destination maxFrames:(NSUInteger)maxFrames;
- (BOOL)renderFrames:(float *)destination
           maxFrames:(NSUInteger)maxFrames
     preBufferFrames:(NSUInteger)preBufferFrames
         didComplete:(BOOL *)didComplete;
- (BOOL)isPlaybackComplete;

@end

@interface RHVoiceEngine : NSObject

- (instancetype)init;

// Синхронний синтез — для preview в App
- (nullable AVAudioPCMBuffer *)synthesize:(NSString *)text
                                    voice:(NSString *)voiceName
                                     rate:(double)rate
                                   volume:(double)volume
                                    pitch:(double)pitch;

// Streaming синтез — для VoiceOver Extension
- (void)synthesizeStreaming:(NSString *)text
                     voice:(NSString *)voiceName
                      rate:(double)rate
                    volume:(double)volume
                     pitch:(double)pitch
                   onChunk:(void(^)(const short* samples, unsigned int count, int sampleRate))chunkCallback;

// Зупинити поточний синтез
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
