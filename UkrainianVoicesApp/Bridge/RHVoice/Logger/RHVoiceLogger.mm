//
//  RHVoiceLogger.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 04.05.2022.
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

#import "RHVoiceLogger.h"

#import "RHVoiceBridge.h"

@implementation RHVoiceLogger

+ (void)logAtLevel:(RHVoiceLogLevel)level format:(NSString *)format, ... {
    
    id<RHVoiceLoggerProtocol> logger = [RHVoiceBridge sharedInstance].params.logger;
    if(logger != nil && [logger respondsToSelector:@selector(logAtLevel:message:)]) {
        va_list args;
        va_start(args, format);
        NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
        [logger logAtLevel:level message:formattedString];
        va_end(args);
    }
}

+ (void)logAtLevel:(RHVoiceLogLevel)level message:(NSString *)message {
    id<RHVoiceLoggerProtocol> logger = [RHVoiceBridge sharedInstance].params.logger;
    if(logger != nil && [logger respondsToSelector:@selector(logAtLevel:message:)]) {
        [logger logAtLevel:level message:message];
    }
}

+ (void)logAtRHVoiceLevel:(RHVoice_log_level)level message:(NSString *)message {
    [self logAtLevel:[self internalLevelToPublic:level] message:message];
}

+ (RHVoiceLogLevel)internalLevelToPublic:(RHVoice_log_level)internal {
    
    switch (internal) {
        case RHVoice_log_level_trace:
            return RHVoiceLogLevelTrace;
        case RHVoice_log_level_debug:
            return RHVoiceLogLevelDebug;
        case RHVoice_log_level_info:
            return RHVoiceLogLevelInfo;
        case RHVoice_log_level_warning:
            return RHVoiceLogLevelWarning;
        case RHVoice_log_level_error:
            return RHVoiceLogLevelError;
    }
}


@end

