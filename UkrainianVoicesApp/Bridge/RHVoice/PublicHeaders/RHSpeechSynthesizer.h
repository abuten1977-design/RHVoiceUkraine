//
//  RHSpeechSynthesizer.h
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

#import <Foundation/Foundation.h>

#import "RHSpeechUtterance.h"

@class RHSpeechSynthesizer;
@class RHSpeechUtteranceClient;

@protocol RHSpeechSynthesizerDelegate <NSObject>
- (void)speechSynthesizer:(RHSpeechSynthesizer *_Nonnull)speechSynthesizer
                didFinish:(RHSpeechUtterance *_Nonnull)utterance;

- (void)speechSynthesizer:(RHSpeechSynthesizer *_Nonnull)speechSynthesizer
      didFailToSynthesize:(RHSpeechUtterance *_Nonnull)utterance
                withError:(NSError *_Nullable)error;
@optional
- (void)speechSynthesizer:(RHSpeechSynthesizer *_Nonnull)speechSynthesizer
     didBeginSynthesizing:(RHSpeechUtterance *_Nonnull)utterance;
@end

NS_ASSUME_NONNULL_BEGIN

@interface RHSpeechSynthesizer : NSObject
@property (nonatomic, weak) id<RHSpeechSynthesizerDelegate> delegate;
@property (nonatomic, readonly) BOOL isSpeaking;
- (void)speak:(RHSpeechUtterance *)utterance;
- (void)synthesizeUtterance:(RHSpeechUtterance *)utterance
               toFileAtPath:(NSString *)path;
- (void)synthesizeUtterance:(RHSpeechUtterance *)utterance
                     client:(RHSpeechUtteranceClient *)client;
- (void)stopAndCancel;
@end

NS_ASSUME_NONNULL_END
