//
//  RHSpeechSynthesisMarker.h
//  RHVoice
//
//  Created by Ihor Shevchuk on 13.09.2022.
//

#import <Foundation/Foundation.h>

typedef enum RHSpeechSynthesisMarkerMark : NSUInteger {
    RHSpeechSynthesisMarkerMarkWord,
    RHSpeechSynthesisMarkerMarkSentence
} RHSpeechSynthesisMarkerMark;

NS_ASSUME_NONNULL_BEGIN

@interface RHSpeechSynthesisMarker : NSObject
@property (nonatomic, readonly) RHSpeechSynthesisMarkerMark mark;
@property (nonatomic, readonly) NSUInteger byteSampleOffset;
@property (nonatomic, readonly) NSRange textRange;
@end

NS_ASSUME_NONNULL_END
