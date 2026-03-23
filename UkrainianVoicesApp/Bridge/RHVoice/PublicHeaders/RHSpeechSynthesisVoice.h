//
//  RHSpeechSynthesisVoice.h
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
#import "RHVersionInfo.h"

@class RHLanguage;

NS_ASSUME_NONNULL_BEGIN

typedef enum RHSpeechSynthesisVoiceGender : NSInteger {
    RHSpeechSynthesisVoiceGenderUnknown,
    RHSpeechSynthesisVoiceGenderMale,
    RHSpeechSynthesisVoiceGenderFemale
} RHSpeechSynthesisVoiceGender;

@interface RHSpeechSynthesisVoice : NSObject
@property (nonatomic, readonly, strong) NSString *name;
@property (nonatomic, readonly, strong) RHLanguage *language;
@property (nonatomic, readonly, strong) NSString *languageCode;
@property (nonatomic, readonly, strong) NSString *identifier;
@property (nonatomic, readonly) RHSpeechSynthesisVoiceGender gender;
@property (nonatomic, readonly, strong, nullable) RHVersionInfo *version;
/// HTML string to be presented along voice name
@property (nonatomic, readonly, strong, nullable) NSString *licenceInfo;
/// Markdown string to be presented on about screen
@property (nonatomic, readonly, strong, nullable) NSString *creatorsInfo;
- (instancetype)init NS_UNAVAILABLE;
+ (NSArray<RHSpeechSynthesisVoice *> *)speechVoices;
@end

NS_ASSUME_NONNULL_END
   
