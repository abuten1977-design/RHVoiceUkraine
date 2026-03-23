//
//  RHSpeechUtterance+Private.h
//  RHVoice
//
//  Created by Ihor Shevchuk on 13.09.2022.
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

#ifndef RHSpeechUtterance_Private_h
#define RHSpeechUtterance_Private_h

#include "core/voice_profile.hpp"
#include "core/quality_setting.hpp"
#include "core/document.hpp"

@interface RHSpeechUtterance (Private)
- (std::unique_ptr<RHVoice::document>)rhVoiceDocument;
@end

#endif /* RHSpeechUtterance_Private_h */
