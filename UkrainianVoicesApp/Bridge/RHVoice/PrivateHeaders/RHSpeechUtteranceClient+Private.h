//
//  RHSpeechUtteranceClient+Private.h
//  RHVoice
//
//  Created by Ihor Shevchuk on 12.09.2022.
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

#ifndef RHSpeechUtteranceClient_Private_h
#define RHSpeechUtteranceClient_Private_h

@class RHSpeechUtteranceClient;
@class RHSpeechUtterance;

@protocol RHSpeechUtteranceClientPrivateDelegate <NSObject>
- (void)utteranceClientDidStart:(RHSpeechUtteranceClient *_Nonnull)utteranceClient;
- (void)utteranceClientDidFinish:(RHSpeechUtteranceClient *_Nonnull)utteranceClient;
@end

#import "RHSpeechUtteranceClient.h"

#include "core/client.hpp"

@interface RHSpeechUtteranceClient (Private)
@property (strong, nonatomic, nullable) RHSpeechUtterance *utterance;
- (std::shared_ptr<RHVoice::client>)client;
- (void)setDelegate:(id<RHSpeechUtteranceClientPrivateDelegate> _Nonnull)deleage;
@end


#endif /* RHSpeechUtteranceClient_Private_h */
