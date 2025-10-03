#import <Foundation/Foundation.h>

@interface RHVoiceStub : NSObject
+ (void)initializeRHVoice;
+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName;
@end
