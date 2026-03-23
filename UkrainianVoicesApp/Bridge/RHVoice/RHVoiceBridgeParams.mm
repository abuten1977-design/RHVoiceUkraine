//
//  RHVoiceBridgeInitParams.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 09.05.2022.
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

#import "RHVoiceBridgeParams.h"

#import "RHVoiceBridgeParams+Private.h"

#include "RHEventLoggerImpl.hpp"

@implementation RHVoiceBridgeParams
+ (instancetype)defaultParams {
    NSString *pathToData = [[NSBundle mainBundle] pathForResource:@"RHVoiceData" ofType:nil];
    if(pathToData.length == 0) {
        NSBundle *rhVoiceBundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"RHVoice_RHVoice" ofType:@"bundle"]];
        pathToData = [rhVoiceBundle pathForResource:@"data" ofType:nil];
    }

    RHVoiceBridgeParams *result = [[RHVoiceBridgeParams alloc] init];
    result.dataPath = pathToData;
    result.configPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    result.pkgPath = result.configPath;
    return result;
}

- (BOOL)isEqual:(id)object {
    RHVoiceBridgeParams *anotherObject = object;
    if(![anotherObject isKindOfClass:[self class]]) {
        return NO;
    }
    
    return [anotherObject.dataPath isEqualToString:self.dataPath] &&
           [anotherObject.logger isEqual:self.logger];
}

- (NSUInteger)hash {
    return [self.dataPath hash] ^ [self.logger hash];
}

- (std::shared_ptr<RHVoice::event_logger>)rhLogger
{
    if(self.logger != nil && [self.logger respondsToSelector:@selector(logAtLevel:message:)]) {
        return std::make_shared<RHEventLoggerImpl>();
    }
    return nullptr;
}
@end
