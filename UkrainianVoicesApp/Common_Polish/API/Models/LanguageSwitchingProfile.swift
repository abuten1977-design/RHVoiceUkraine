//
//  LanguageSwitchingProfile.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 3/22/25.
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

import Foundation

public struct LanguageSwitchingProfile: Decodable, Sendable {
    public let profile: String?
    public let languages: [Language]
    public var voices: [Voice] {
        return profileVoices ?? []
    }
    let profileVoices: [Voice]?
    
    enum CodingKeys: String, CodingKey {
        case profile
        case languages
        case profileVoices = "voices"
    }
}
