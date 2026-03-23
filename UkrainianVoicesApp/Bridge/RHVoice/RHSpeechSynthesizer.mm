//
//  RHSpeechSynthesizer.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 03.05.2022.
//
//
//  Copyright (C) 2022–2024 Ihor Shevchuk
//  Copyright (C) 2025 Non-Routine LLC
//  Contact: contact@nonroutine.com
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#import "RHSpeechSynthesizer.h"

#import <AVFAudio/AVFAudio.h>

#include "RHSpeechUtterance+Private.h"
#import "RHSpeechUtteranceClient+Private.h"

#import "NSString+Additions.h"
#import "NSFileManager+Additions.h"
#import "NSString+stdStringAddtitons.h"

#include "RHVoiceWrapper.h"
#import "RHVoiceLogger.h"

#define CALLDELEGATE_WITH_ERROR_IF_NEEDED_AND_EXIT(errorObject) \
    if((errorObject) != nil) { \
        [self callDelegateWithError:error forUtterance:utterance]; \
        return; \
    }

@interface RHSpeechSynthesizer() <AVAudioPlayerDelegate,
                                  RHSpeechUtteranceClientPrivateDelegate> {
    BOOL _isSpeaking;
    dispatch_queue_t underlyingQueue;
}
@property (strong, atomic) AVAudioPlayer *player;
@property (strong, atomic) RHSpeechUtterance *currentUtterance;
@property (strong, atomic) RHSpeechUtteranceClient *currentUtteranceClient;

@end

@implementation RHSpeechSynthesizer

- (instancetype)init {
    self = [super init];
    if (self) {
        underlyingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    }
    
    return self;
}

#pragma mark - Public

- (void)speak:(RHSpeechUtterance *)utterance {
    
    __weak RHSpeechSynthesizer *weakSelf = self;
    dispatch_async(underlyingQueue, ^{
        [weakSelf speakInternal:utterance];
    });
}

- (void)synthesizeUtterance:(RHSpeechUtterance *)utterance
               toFileAtPath:(NSString *)path {
    __weak RHSpeechSynthesizer *weakSelf = self;
    dispatch_async(underlyingQueue, ^{
        [weakSelf synthesizeInternalUtterance:utterance
                                 toFileAtPath:path];
    });
}

- (void)synthesizeUtterance:(RHSpeechUtterance *)utterance
                     client:(RHSpeechUtteranceClient *)client {
    if(client == nil) {
        if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFinish:)]) {
            [self.delegate speechSynthesizer:self didFinish:utterance];
        }
        return;
    }
    
    __weak RHSpeechSynthesizer *weakSelf = self;
    dispatch_async(underlyingQueue, ^{
        [weakSelf synthesizeInternalUtterance:utterance
                                       client:client];
    });
}

- (BOOL)isSpeaking {
    return _isSpeaking;
}

- (void)stopAndCancel {
    [self.player stop];
    [self.currentUtteranceClient cancel];
    
    __weak RHSpeechSynthesizer *weakSelf = self;
    dispatch_async(underlyingQueue, ^{
        [weakSelf cleanUp];
    });
}

#pragma mark - Private

- (void)cleanUp {
    if(self.currentUtterance != nil) {
        if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFinish:)]) {
            [self.delegate speechSynthesizer:self didFinish:self.currentUtterance];
        }
    }
    self.currentUtterance = nil;
    self.currentUtteranceClient = nil;
    
    if (self.player != nil) {
        [[NSFileManager defaultManager] removeItemAtURL:self.player.url error:nil];
        self.player = nil;
        
#if TARGET_OS_IPHONE
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
#endif
        [[NSFileManager defaultManager] RHRemoveTempFolderIfNeededPath:[NSString RHTemporaryFolderPath]];
    }
}

- (void)speakInternal:(RHSpeechUtterance *)utterance {
    
    if(utterance.isEmpty) {
        if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFinish:)]) {
            [self.delegate speechSynthesizer:self didFinish:utterance];
        }
        return;
    }
    
    _isSpeaking = YES;
    [[NSFileManager defaultManager] RHCreateTempFolderIfNeededPath:[NSString RHTemporaryFolderPath]];
    NSString *path = [NSString RHTemporaryPathWithExtesnion:@"wav"];
    
    [self synthesizeInternalUtterance:utterance
                         toFileAtPath:path];

    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    CALLDELEGATE_WITH_ERROR_IF_NEEDED_AND_EXIT(error);
#if TARGET_OS_IPHONE 
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    CALLDELEGATE_WITH_ERROR_IF_NEEDED_AND_EXIT(error);
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    CALLDELEGATE_WITH_ERROR_IF_NEEDED_AND_EXIT(error);
#endif
    
    self.currentUtterance = utterance;
    self.player.delegate = self;
    self.player.volume = 1;
    self.player.rate = 1;
    [self.player prepareToPlay];
    [self.player play];
    
    while (self.player.isPlaying)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    }
    
    _isSpeaking = NO;
}

- (void)synthesizeInternalUtterance:(RHSpeechUtterance *)utterance
                             client:(RHSpeechUtteranceClient *)client {
    if(utterance.voice == nil) {
        NSError *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:404 userInfo:nil];
        CALLDELEGATE_WITH_ERROR_IF_NEEDED_AND_EXIT(error);
    }
    
    self.currentUtterance = utterance;
    self.currentUtteranceClient = client;
    
    [client setDelegate:self];
    client.utterance = utterance;
    
    std::unique_ptr<RHVoice::document> doc = [utterance rhVoiceDocument];
    
    doc->set_owner(*client.client);
    try {
        doc->synthesize();
    } catch(const std::exception& exception) {
        NSString *exceptionMessage = @"";
        if(exception.what() != nil) {
            exceptionMessage = STDStringToNSString(exception.what());
        }
        [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"Exception happened during synthesize utterance('%@'). Exception:%@", utterance.ssml, exceptionMessage];
        [client cancel];
    }

    [self cleanUp];
}

- (void)synthesizeInternalUtterance:(RHSpeechUtterance *)utterance
                       toFileAtPath:(NSString *)path {
    if(utterance.isEmpty) {
        if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFinish:)]) {
            [self.delegate speechSynthesizer:self didFinish:utterance];
        }
        return;
    }
    
    if([self.delegate respondsToSelector:@selector(speechSynthesizer:didBeginSynthesizing:)]) {
        [self.delegate speechSynthesizer:self didBeginSynthesizing:utterance];
    }
    
    if(utterance.voice == nil) {
        NSError *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:404 userInfo:nil];
        CALLDELEGATE_WITH_ERROR_IF_NEEDED_AND_EXIT(error);
    }
    
    RHVoice::audio_player player(NSStringToSTDString(path));
    player.set_buffer_size(20);
    player.set_sample_rate(24000);
    
    std::unique_ptr<RHVoice::document> doc = [utterance rhVoiceDocument];
    
    doc->set_owner(player);
    try {
        doc->synthesize();
    } catch(const std::exception& exception) {
        NSString *exceptionMessage = @"";
        if(exception.what() != nil) {
            exceptionMessage = STDStringToNSString(exception.what());
        }
        [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"Exception happened during synthesize utterance('%@'). Exception:%@", utterance.ssml, exceptionMessage];
    }
    player.finish();
    
    if(![self isSpeaking]) {
        if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFinish:)]) {
            [self.delegate speechSynthesizer:self didFinish:utterance];
        }
        self.currentUtterance = nil;
    }
}

- (void)callDelegateWithError:(NSError *)error
                 forUtterance:(RHSpeechUtterance *)utterance {
    if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFailToSynthesize:withError:)]) {
        [self.delegate speechSynthesizer:self didFailToSynthesize:utterance withError:error];
    }
    [self cleanUp];
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self cleanUp];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
    [self callDelegateWithError:error forUtterance:self.currentUtterance];
}

#pragma mark - RHSpeechUtteranceClientPrivateDelegate
- (void)utteranceClientDidStart:(RHSpeechUtteranceClient *_Nonnull)utteranceClient {
    if([self.delegate respondsToSelector:@selector(speechSynthesizer:didBeginSynthesizing:)]) {
        [self.delegate speechSynthesizer:self didBeginSynthesizing:utteranceClient.utterance];
    }
}

- (void)utteranceClientDidFinish:(RHSpeechUtteranceClient *_Nonnull)utteranceClient {
    if([self.delegate respondsToSelector:@selector(speechSynthesizer:didFinish:)]) {
        [self.delegate speechSynthesizer:self didFinish:utteranceClient.utterance];
    }
    self.currentUtterance = nil;
}
@end
