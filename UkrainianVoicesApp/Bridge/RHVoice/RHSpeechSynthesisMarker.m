//
//  RHSpeechSynthesisMarker.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 13.09.2022.
//

#import "RHSpeechSynthesisMarker.h"

@implementation RHSpeechSynthesisMarker
@synthesize mark = _mark;
@synthesize byteSampleOffset = _byteSampleOffset;
@synthesize textRange = _textRange;

- (instancetype)initWithMark:(RHSpeechSynthesisMarkerMark)mark
                   textRange:(NSRange)textRange {
    self = [super init];
    if (self) {
        _mark = mark;
        _byteSampleOffset = 0;
        _textRange = textRange;
    }
    
    return self;
}

- (void)setByteSampleOffset:(NSInteger)byteSampleOffset {
    _byteSampleOffset = byteSampleOffset;
}
@end
