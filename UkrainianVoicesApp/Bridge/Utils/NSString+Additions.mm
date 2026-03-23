//
//  NSString+Additions.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 29.04.2022.
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

#import "NSString+Additions.h"

#import "RHVoiceLogger.h"

#import "NSString+stdStringAddtitons.h"

@implementation NSString (Additions)

- (size_t)RHutf8Size {
    std::string string = NSStringToSTDString(self);
    return string.size();
}

- (NSRange)RHutf16RangeFromUTF8:(NSRange)range
                 utf8StartIndex:(NSInteger)utf8Index
                utf16StartIndex:(NSInteger)utf16Index
{
    NSRange rangeToEnumerate = NSMakeRange(utf16Index, [self length] - utf16Index);
    if (![self RHisValidRange:rangeToEnumerate]) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    __block NSUInteger location = NSNotFound;
    __block NSUInteger length = 0;    
    __block NSInteger index = utf8Index;
    __block NSInteger size = 0;

    [self enumerateSubstringsInRange:rangeToEnumerate
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString * _Nullable nsChar, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {

        const size_t sizeOfCharacter = nsChar.RHutf8Size;
        index += sizeOfCharacter;
        const BOOL isLocationFound = location != NSNotFound;

        if(isLocationFound) {
            size += sizeOfCharacter;
        }

        if(index == range.location) {
            location = substringRange.location + 1;
            size = 0;
        }

        if(isLocationFound && size == range.length) {
            length = substringRange.location - location + 1;
            *stop = YES;
        }
    }];
    
    if(length == 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    return NSMakeRange(location, length);
}

- (BOOL)RHisValidRange:(NSRange)range {
    const BOOL isLocationValid = range.location <= self.length;
    const BOOL isEndValid = (range.location + range.length) <= self.length;
    return isLocationValid && isEndValid;
}

- (NSRange)RHutf16RangeFromUTF8:(NSRange)range {
    return [self RHutf16RangeFromUTF8:range
                       utf8StartIndex:0
                      utf16StartIndex:0];
}

- (NSDictionary<NSString *, NSString *> * __nullable)RHFileAtPathToDictionary {
    NSError *error = nil;
    NSString *stringInfo = [NSString stringWithContentsOfFile:self encoding:NSUTF8StringEncoding error: &error];
    if(error) {
        [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"Can not read file due to the error:%@", error];
        return nil;
    }
    NSArray <NSString *> *arrayOfPairs = [stringInfo componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    if(arrayOfPairs.count == 0) {
        [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"File is empty. Returning nil"];
        return nil;
    }
    NSMutableArray<NSString *> *keys = [[NSMutableArray alloc] initWithCapacity:arrayOfPairs.count];
    NSMutableArray<NSString *> *values = [[NSMutableArray alloc] initWithCapacity:arrayOfPairs.count];
    for(NSString *pair in arrayOfPairs) {
        if(pair.length == 0) {
            continue;
        }
        NSArray *keyValue = [pair componentsSeparatedByString:@"="];
        
        NSString *key = [keyValue firstObject];
        NSString *value = [keyValue lastObject];
        
        if(keyValue.count == 2 &&
           key.length > 0 &&
           value.length > 0) {
            [keys addObject:key];
            [values addObject:value];
        } else {
            [RHVoiceLogger logAtLevel:RHVoiceLogLevelWarning format:@"Skipping pair(%@) because it does not contain required format: key=value", pair];
        }
    }
    
    return [[NSDictionary alloc] initWithObjects:values forKeys:keys];
}

+ (NSString *)RHTemporaryFolderPath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"RHVoice"];
}

+ (NSString *)RHTemporaryPathWithExtesnion:(NSString *)extesnion {
    NSString *uuidString = [NSUUID UUID].UUIDString;
    return [[self RHTemporaryFolderPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", uuidString, extesnion]];
}
@end
