#import <Foundation/Foundation.h>

@interface RHSpeechSynthesizer : NSObject
- (void)setParam:(NSString *)name value:(int)value;
- (void)say:(NSString *)text toFile:(NSString *)path;
@end
