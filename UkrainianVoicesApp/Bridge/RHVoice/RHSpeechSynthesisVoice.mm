//
//  RHSpeechSynthesisVoice.m
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

#import "RHSpeechSynthesisVoice.h"

#import "RHVoiceBridge+PrivateAdditions.h"
#import "RHVersionInfo+Private.h"
#import "RHLanguage+Private.h"
#import "NSString+stdStringAddtitons.h"

@interface RHSpeechSynthesisVoice() {
    RHVoice::voice_list::const_iterator voice_info;
}
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *dataPath;
@property (nonatomic, strong) RHLanguage *language;
@property (nonatomic, strong) NSString *countryCode;
@property (nonatomic, strong) NSString *voiceLanguageCode;
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, assign) RHSpeechSynthesisVoiceGender gender;
@end

@implementation RHSpeechSynthesisVoice

#pragma mark - Public

- (NSString *)languageCode {
    
    NSString *languageCode = [[self language] code];
    
    const BOOL isLanguageCodeEmpty = languageCode == nil || [languageCode isEqualToString:@""];
    const BOOL isCountryCodeEmpty = [self voiceLanguageCode] == nil || [[self voiceLanguageCode] isEqualToString:@""];
    
    if (isLanguageCodeEmpty && isCountryCodeEmpty) {
        return @"";
    }
    
    if(isLanguageCodeEmpty) {
        return [self voiceLanguageCode];
    }
    
    if(isCountryCodeEmpty) {
        return languageCode;
    }

    return [NSString stringWithFormat:@"%@-%@", languageCode, [self voiceLanguageCode]];
}

- (RHVersionInfo * __nullable)version {
    return [[RHVersionInfo alloc] initWith:[[self dataPath] stringByAppendingPathComponent:@"voice.info"]];
}

- (NSString * __nullable)licenceInfo {
    return [[NSString alloc] initWithContentsOfFile:[[self dataPath]
                                                     stringByAppendingPathComponent:@"attrib.html"]
                                           encoding:NSUTF8StringEncoding
                                              error:nil];
}

- (NSString * __nullable)creatorsInfo {
    return [[NSString alloc] initWithContentsOfFile:[[self dataPath]
                                                     stringByAppendingPathComponent:@"README.md"]
                                           encoding:NSUTF8StringEncoding
                                              error:nil];
}

+ (NSArray<RHSpeechSynthesisVoice *> *)speechVoices {
    if(![[RHVoiceBridge sharedInstance] engine].get()) {
        return @[];
    }
    
    if([[RHVoiceBridge sharedInstance] voices].empty()) {
        return @[];
    }
    
    NSMutableArray *result = [[NSMutableArray alloc] init];
    
    const RHVoice::voice_list &voices = [[RHVoiceBridge sharedInstance] voices];
    for (auto voice = voices.begin(); voice != voices.end(); ++voice) {
        [result addObject:[[RHSpeechSynthesisVoice alloc] initWith:voice]];
    }
    
    return [result copy];
}

- (BOOL)isEqual:(id)object {
    RHSpeechSynthesisVoice *other = object;
    if(![other isKindOfClass:[RHSpeechSynthesisVoice class]]) {
        return NO;
    }
    
    return [[self name] isEqualToString:[other name]]
        && [[self identifier] isEqualToString: [other identifier]]
        && [[self language] isEqual: [other language]]
        && [self gender] == [other gender];
}

- (NSUInteger)hash {
    return [[self name] hash]
         ^ [[self identifier] hash]
         ^ [[self language] hash]
         ^ [self gender];
}

#pragma mark - Private

- (instancetype)initWith:(RHVoice::voice_list::const_iterator)voice_info {
    self = [super init];
    if(self) {
        self->voice_info = voice_info;
        self.dataPath = STDStringToNSString(voice_info->get_data_path());
        self.name = STDStringToNSString(voice_info->get_name());
        self.language = [[RHLanguage alloc] initWith:*voice_info->get_language()];
        self.voiceLanguageCode = STDStringToNSString(voice_info->get_alpha2_country_code());
        self.identifier = STDStringToNSString(voice_info->get_id());
        self.gender = [RHSpeechSynthesisVoice genderFromRHVoiceGender:voice_info->get_gender()];
    }
    return self;
}

- (RHVoice::voice_list::const_iterator)voiceInfo {
    return voice_info;
}

+ (RHSpeechSynthesisVoiceGender)genderFromRHVoiceGender:(RHVoice_voice_gender)gender {
    switch (gender) {
        case RHVoice_voice_gender_unknown:
            return RHSpeechSynthesisVoiceGenderUnknown;
        case RHVoice_voice_gender_male:
            return RHSpeechSynthesisVoiceGenderMale;
        case RHVoice_voice_gender_female:
            return RHSpeechSynthesisVoiceGenderFemale;
    }
}
@end
