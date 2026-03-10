//
//  RHVoiceParameters.h
//  RHVoiceUkrainianSynthesizer
//
//  Ukrainian Speech Synthesizer for iOS VoiceOver
//  Based on RHVoice engine with Ukrainian voices
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface RHVoiceParameters : NSObject

@property (nonatomic, readonly) CGFloat max;
@property (nonatomic, readonly) CGFloat min;
@property (nonatomic, readonly) CGFloat defaultValue;

- (instancetype)initWithMax:(CGFloat)max
                        min:(CGFloat)min
                 andDefault:(CGFloat)defaultValue;

+ (RHVoiceParameters *)volumeParameters;
+ (RHVoiceParameters *)rateParameters;
+ (RHVoiceParameters *)pitchParameters;

@end

NS_ASSUME_NONNULL_END
