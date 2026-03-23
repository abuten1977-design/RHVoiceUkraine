//
//  RHSpeechUtterance.h (MODIFIED FOR TURBO-PARAMS)
//

#import <Foundation/Foundation.h>
#import "RHSpeechSynthesisVoice.h"

@interface RHSpeechUtterance : NSObject

@property (nonatomic, readonly) NSString *ssml;
@property (nonatomic, strong) RHSpeechSynthesisVoice *voice;

// Новые параметры (Твои 'ускорители')
@property (nonatomic, assign) double rateMultiplier;
@property (nonatomic, assign) int wordPause;
@property (nonatomic, assign) int punctuationPause;

+ (instancetype)utteranceWithSSML:(NSString *)ssml;
- (instancetype)initWithSSML:(NSString *)ssml;

@property (nonatomic, readonly) BOOL isEmpty;

@end
