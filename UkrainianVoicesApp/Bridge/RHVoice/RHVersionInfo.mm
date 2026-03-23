//
//  RHVersionInfo.m
//  RHVoiceFramework
//
//  Created by Ihor Shevchuk on 18.09.2022.
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

#import "RHVersionInfo.h"

#import "RHVoiceLogger.h"
#import "NSString+Additions.h"

@interface RHVersionInfo() {
    NSInteger _format;
    NSInteger _revision;
}
@end

@implementation RHVersionInfo

- (instancetype __nullable)initWith:(NSString *)pathToInfoFile {

    NSDictionary *map = [pathToInfoFile RHFileAtPathToDictionary];
    NSString *format = [map valueForKey:@"format"];
    NSString *revision = [map valueForKey:@"revision"];
    if(format.length > 0 &&
       revision.length > 0) {
        return [self initWith:[format integerValue] revision:[revision integerValue]];
    }
    
    [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"There is no format and revision values in file at path:%@", pathToInfoFile];
    return nil;
}

- (instancetype)initWith:(NSInteger)format
                revision:(NSInteger)revision {
    self = [super init];
    if (self) {
        _format = format;
        _revision = revision;
    }
    return self;
}

#pragma mark - Public

- (NSInteger)format {
    return _format;
}

- (NSInteger)revision {
    return _revision;
}

- (NSString *)string {
    return [NSString stringWithFormat:@"%li.%li", self.format, self.revision];
}
@end
