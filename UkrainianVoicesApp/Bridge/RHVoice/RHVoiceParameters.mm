//
//  RHVoiceParameters.m
//  RHVoiceFramework
//
//  Created by Ihor Shevchuk on 14.01.2023.
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

#import "RHVoiceParameters.h"

#include "core/params.hpp"

@implementation RHVoiceParameters
- (instancetype)initWithMax:(CGFloat)max
                        min:(CGFloat)min
                 andDefault:(CGFloat)defaultValue {
    self = [super init];
    if (self) {
        _max = max;
        _min = min;
        _defaultValue = defaultValue;
    }
    return self;
}

+ (RHVoiceParameters *)volumeParameters {
    RHVoice::voice_params defaultParams;
    return [[RHVoiceParameters alloc] initWithMax:defaultParams.max_volume.get()
                                              min:defaultParams.min_volume.get()
                                       andDefault:defaultParams.default_volume.get()];
}

+ (RHVoiceParameters *)rateParameters {
    RHVoice::voice_params defaultParams;
    return [[RHVoiceParameters alloc] initWithMax:defaultParams.max_rate.get()
                                              min:defaultParams.min_rate.get()
                                       andDefault:defaultParams.default_rate.get()];
}

@end
