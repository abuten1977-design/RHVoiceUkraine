//
//  RHLanguage.m
//  RHVoiceFramework
//
//  Created by Ihor Shevchuk on 15.09.2022.
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

#import "RHLanguage.h"

#import "RHLanguage+Private.h"
#import "RHVersionInfo+Private.h"
#import "RHSpeechSynthesisVoice.h"
#import "NSString+stdStringAddtitons.h"

@interface RHLanguage ()
@property(nonatomic, strong) NSString *code;
@property(nonatomic, strong) NSString *country;
@property(nonatomic, strong) RHVersionInfo *version;

@end

@implementation RHLanguage

- (NSArray<RHSpeechSynthesisVoice *> *)voices {
    
    NSArray<RHSpeechSynthesisVoice *> *result = [[RHSpeechSynthesisVoice speechVoices] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        RHSpeechSynthesisVoice *object = evaluatedObject;
        if(![object isKindOfClass:[RHSpeechSynthesisVoice class]]) {
            return NO;
        }
        return [object.language isEqual:self];
    }]];

    return result;
}

- (BOOL)isEqual:(id)object {
    RHLanguage *other = object;
    if(![other isKindOfClass:[RHLanguage class]]) {
        return NO;
    }
    
    return [[other code] isEqualToString:[self code]] &&
           [[other country] isEqual:[self country]];
}

- (NSUInteger)hash {
    return [[self code] hash] ^ [[self country] hash];
}

#pragma mark - Private

- (instancetype)initWith:(const RHVoice::language_info &)language {
    self = [super init];
    if(self) {
        self.code = STDStringToNSString(language.get_alpha2_code());
        self.country = STDStringToNSString(language.get_name());
        NSString *dataPath = STDStringToNSString(language.get_data_path());
        self.version = [[RHVersionInfo alloc] initWith:[dataPath stringByAppendingPathComponent:@"language.info"]];
    }
    return self;
}

@end
