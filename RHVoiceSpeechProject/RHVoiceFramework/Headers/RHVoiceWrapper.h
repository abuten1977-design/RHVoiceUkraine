
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RHVoiceWrapper : NSObject

+ (void)initializeRHVoice;
+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName;

@end

NS_ASSUME_NONNULL_END
