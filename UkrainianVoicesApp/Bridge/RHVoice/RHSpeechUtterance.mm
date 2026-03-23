//
//  RHSpeechUtterance.m
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

#import "RHSpeechUtterance.h"

#import "RHVoiceBridge+PrivateAdditions.h"
#include "RHSpeechUtterance+Private.h"
#include "RHSpeechSynthesisVoice+Private.h"

#import "NSString+stdStringAddtitons.h"

@interface RHSpeechUtterance()
@end

@implementation RHSpeechUtterance

- (instancetype)init {
    return [self initWithText:nil];
}

- (instancetype)initWithText:(NSString * _Nullable)text {
    
    NSString *textInternal = text;
    if(textInternal == nil) {
        textInternal = @"";
    }
    
    return [self initWithSSML:[NSString stringWithFormat:@"<speak>%@</speak>", textInternal]];;
}

- (instancetype)initWithSSML:(NSString * _Nullable)ssml {
    self = [super init];
    if(self) {
        _ssml = ssml;
        self.rate = 1.0;
        self.volume = 1.0;
        self.quality = RHSpeechUtteranceQualityStandart;
        self.voice = [[RHSpeechSynthesisVoice speechVoices] firstObject];
    }
    return self;
}

- (BOOL)isEmpty {
    return self.ssml.length == 0 || self.ssml == nil || [self.ssml isEqualToString:@"<speak></speak>"];
}

#pragma mark - Privates

- (const std::string)rhVoiceQuality {
    switch (self.quality) {
        case RHSpeechUtteranceQualityMin:
            return "minimum";
        case RHSpeechUtteranceQualityStandart:
            return "standard";
        case RHSpeechUtteranceQualityMax:
            return "maximum";
        default:
            return "standard";
    }
}

- (std::unique_ptr<RHVoice::document>)rhVoiceDocument {
    std::unique_ptr<RHVoice::document> doc;
    RHVoice::voice_profile voiceProfile = [RHVoiceBridge sharedInstance].engine->create_voice_profile(NSStringToSTDString(self.voiceProfile ?: self.voice.name));
    
    /// Using wsting or any other utf16 string is causing huge memory usage that is much bigger than 60 MB that is a limit for app extention
    std::string textToSpeak = NSStringToSTDString(self.ssml);
    doc = RHVoice::document::create_from_ssml([RHVoiceBridge sharedInstance].engine,
                                     textToSpeak.cbegin(),
                                     textToSpeak.cend(),
                                     voiceProfile);
    doc->speech_settings.relative.rate = self.rate;
    doc->speech_settings.relative.volume = self.volume;
    doc->quality.set_from_string(self.rhVoiceQuality);
    
    return doc;
}
@end
