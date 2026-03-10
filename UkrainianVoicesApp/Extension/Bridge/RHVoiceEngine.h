//
//  RHVoiceEngine.h
//  Ukrainian Voices Extension
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RHVoiceEngine : NSObject

- (instancetype)init;

- (nullable AVAudioPCMBuffer *)synthesize:(NSString *)text
                                    voice:(NSString *)voiceName
                                     rate:(double)rate
                                   volume:(double)volume
                                    pitch:(double)pitch;

@end

NS_ASSUME_NONNULL_END
