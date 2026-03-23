//
//  RHSpeechUtteranceClient.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 12.09.2022.
//

#import <Foundation/Foundation.h>

#import "RHSpeechUtteranceClient.h"
#import "RHSpeechUtteranceClient+Private.h"
#import "RHSpeechSynthesisMarker.h"
#import "RHSpeechSynthesisMarker+Private.h"

#import "NSString+Additions.h"
#import "RHSpeechUtterance.h"
#import "NSString+stdStringAddtitons.h"

#include <memory>
#include <stdexcept>
#include <iostream>
#include <fstream>
#include <iterator>
#include <algorithm>
#include <queue>
#include <vector>

#include "core/engine.hpp"
#include "core/document.hpp"
#include "core/client.hpp"
#include "audio.hpp"

namespace RHVoice
{
class RHSpeechClient: public client
{
public:
    explicit RHSpeechClient(RHSpeechUtteranceClient *delegate);
    bool play_speech(const short* samples,std::size_t count) override;
    event_mask get_supported_events() const override;
    bool word_starts(std::size_t position,std::size_t length) override;
    bool sentence_starts(std::size_t position,std::size_t length) override;
    unsigned int get_audio_buffer_size() const override;
    void done() override;
    
private:
    RHSpeechUtteranceClient * _delegate;
};
}

@interface RHSpeechUtteranceClient() {
    std::shared_ptr<RHVoice::RHSpeechClient> client;
    __weak id<RHSpeechUtteranceClientPrivateDelegate> privateDeleage;
    RHSpeechUtterance *_utterance;
    NSUInteger possition;
    
    dispatch_queue_t markersQueue;
    RHSpeechSynthesisMarker *lastWordMarker;
    RHSpeechSynthesisMarker *lastSentenceMarker;
    NSInteger lastWordBeginUTF8Index;
    NSInteger lastWordBeginUTF16Index;
    NSInteger lastSentenceBeginUTF8Index;
    NSInteger lastSentenceBeginUTF16Index;
}
@property(atomic, assign) RHSpeechUtteranceClientStatus status;
@property(nonatomic, assign) int bufferSize;
- (BOOL)speechClientSynthesized:(std::vector<short> &)levels __attribute__((objc_direct));
- (void)speechClientFinished __attribute__((objc_direct));
- (BOOL)didStartWordWithRange:(NSRange)range __attribute__((objc_direct));
- (BOOL)didStartSentenceWithRange:(NSRange)range __attribute__((objc_direct));
- (int)audioBufferSize __attribute__((objc_direct));
@end


namespace RHVoice
{
    event_mask RHSpeechClient::get_supported_events() const {
        return event_audio |
               event_done |
               event_word_starts |
               event_sentence_starts;
    }
    
    RHSpeechClient::RHSpeechClient(RHSpeechUtteranceClient *delegate):_delegate(delegate) {}
    
    bool RHSpeechClient::play_speech(const short* samples, std::size_t count) {
        std::vector<short> levels(samples, samples + count);
        return [_delegate speechClientSynthesized:levels];
    }

    bool RHSpeechClient::word_starts(std::size_t position, std::size_t length) {
        return [_delegate didStartWordWithRange:NSMakeRange(position, length)];
    }
    
    bool RHSpeechClient::sentence_starts(std::size_t position, std::size_t length) {
        return [_delegate didStartSentenceWithRange:NSMakeRange(position, length)];
    }

    unsigned int RHSpeechClient::get_audio_buffer_size() const {
       return [_delegate audioBufferSize];
    }

    void RHSpeechClient::done() {
        [_delegate speechClientFinished];
        _delegate = nil;
    }
}

@implementation RHSpeechUtteranceClient

- (instancetype)initWithAudioBufferSize:(int)audioBufferSize {
    self = [super init];
    if (self) {
        client = std::make_shared<RHVoice::RHSpeechClient>(self);
        self.status = RHSpeechUtteranceClientStatusCreated;
        lastSentenceMarker = lastWordMarker = nil;
        lastWordBeginUTF8Index = 0;
        lastWordBeginUTF16Index = 0;
        lastSentenceBeginUTF8Index = 0;
        lastSentenceBeginUTF16Index = 0;
        self.bufferSize = audioBufferSize;
        
        
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_USER_INITIATED,
                                                                             0);
        NSString *queueName = [NSString stringWithFormat:@"%@.markersQueue", NSStringFromClass([self class])];
        markersQueue = dispatch_queue_create(NSStringToSTDString(queueName).c_str(), attr);
    }
    return self;
}

- (BOOL)completed {
    return self.status == RHSpeechUtteranceClientStatusCompleted || self.status == RHSpeechUtteranceClientStatusCanceled;
}

- (BOOL)isRendering {
    return self.status == RHSpeechUtteranceClientStatusRendering;
}

- (void)cancel {
    self.status = RHSpeechUtteranceClientStatusCanceled;
}

#pragma mark - Privates

- (std::shared_ptr<RHVoice::client>)client {
    return client;
}

- (void)setDelegate:(id<RHSpeechUtteranceClientPrivateDelegate>)deleage {
    privateDeleage = deleage;
}

- (void)setUtterance:(RHSpeechUtterance *)utterance {
    _utterance = utterance;
}

- (RHSpeechUtterance *)utterance {
    return _utterance;
}

#pragma mark - RHSpeechClientDelegate

- (int)audioBufferSize __attribute__((objc_direct)); {
    return self.bufferSize;
}

- (BOOL)speechClientSynthesized:(std::vector<short> &)levels __attribute__((objc_direct)); {
    if (self.status == RHSpeechUtteranceClientStatusCreated) {
        self.status = RHSpeechUtteranceClientStatusRendering;
        possition = 0;
        [privateDeleage utteranceClientDidStart:self];
    }
    
    if(self.status == RHSpeechUtteranceClientStatusCanceled) {
        return NO;
    }
    
    size_t levelsSize = levels.size();
    __typeof(self) __weak weakSelf = self;
    dispatch_async(markersQueue, ^{
        __typeof(self) __strong strongSelf = weakSelf;
        if(strongSelf->lastWordMarker || strongSelf->lastSentenceMarker) {
            strongSelf->lastWordMarker.byteSampleOffset = possition;
            strongSelf->lastSentenceMarker.byteSampleOffset = possition;
            
            if([strongSelf.markerDelegate respondsToSelector:@selector(utteranceClientDidReceiveMarkers:)]) {
                
                NSMutableArray *markers = [[NSMutableArray alloc] initWithCapacity:2];
                if(strongSelf->lastWordMarker) {
                    [markers addObject:strongSelf->lastWordMarker];
                }
                if(strongSelf->lastSentenceMarker) {
                    [markers addObject:strongSelf->lastSentenceMarker];
                }
                
                [strongSelf.markerDelegate utteranceClientDidReceiveMarkers:[markers copy]];
            }
            
            strongSelf->lastWordMarker = nil;
            strongSelf->lastSentenceMarker = nil;
        }
        strongSelf->possition += levelsSize;
    });
    
    [self.markerDelegate utteranceClientDidReceiveSamples:levels.data() withSize:levels.size()];
    
    return YES;
}

- (void)speechClientFinished __attribute__((objc_direct)); {
    self.status = RHSpeechUtteranceClientStatusCompleted;
    if([privateDeleage respondsToSelector:@selector(utteranceClientDidFinish:)]) {
        [privateDeleage utteranceClientDidFinish:self];
    }
}

- (BOOL)didStartWordWithRange:(NSRange)range __attribute__((objc_direct)); {
    __typeof(self) __weak weakSelf = self;
    dispatch_async(markersQueue, ^{
        __typeof(self) __strong strongSelf = weakSelf;
        NSRange utf16range = [strongSelf.utterance.ssml RHutf16RangeFromUTF8:range
                                                              utf8StartIndex:lastWordBeginUTF8Index
                                                             utf16StartIndex:lastWordBeginUTF16Index];
        strongSelf->lastWordBeginUTF8Index = range.location;
        strongSelf->lastWordBeginUTF16Index = utf16range.location;
        strongSelf->lastWordMarker = [[RHSpeechSynthesisMarker alloc] initWithMark:RHSpeechSynthesisMarkerMarkWord 
                                                                         textRange:utf16range];
    });
    return YES;
}

- (BOOL)didStartSentenceWithRange:(NSRange)range __attribute__((objc_direct)); {
    __typeof(self) __weak weakSelf = self;
    dispatch_async(markersQueue, ^{
        __typeof(self) __strong strongSelf = weakSelf;
        NSRange utf16range = [strongSelf.utterance.ssml RHutf16RangeFromUTF8:range
                                                        utf8StartIndex:lastSentenceBeginUTF8Index
                                                       utf16StartIndex:lastSentenceBeginUTF16Index];
        strongSelf->lastSentenceBeginUTF8Index = range.location;
        strongSelf->lastSentenceBeginUTF16Index = utf16range.location;
        strongSelf->lastWordMarker = [[RHSpeechSynthesisMarker alloc] initWithMark:RHSpeechSynthesisMarkerMarkSentence 
                                                                         textRange:utf16range];
    });
    return YES;
}

@end
