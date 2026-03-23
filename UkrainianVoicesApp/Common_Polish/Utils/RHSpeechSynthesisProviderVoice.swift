//
//  RHSpeechSynthesisProviderVoice.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 22.04.2023.
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
import AVFoundation

public class RHSpeechSynthesisProviderVoice: AVSpeechSynthesisProviderVoice, Codable, @unchecked Sendable {

    private enum CodingKeys: String, CodingKey {
        case name
        case identifier
        case primaryLanguages
        case supportedLanguages
        case voiceSize
        case version
        case gender
        case age
    }

    override init(name: String, identifier: String, primaryLanguages: [String], supportedLanguages: [String]) {
        super.init(name: name,
                   identifier: identifier,
                   primaryLanguages: primaryLanguages,
                   supportedLanguages: supportedLanguages)
    }

    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let primaryLanguages = try container.decode([String].self, forKey: .primaryLanguages)
        let supportedLanguages = try container.decode([String].self, forKey: .supportedLanguages)
        let voiceSize = try container.decode(Int64.self, forKey: .voiceSize)
        let genderRaw = try container.decode(Int.self, forKey: .gender)
        let age = try container.decode(Int.self, forKey: .age)

        let gender = AVSpeechSynthesisVoiceGender(rawValue: genderRaw)

        self.init(name: name,
                   identifier: identifier,
                   primaryLanguages: primaryLanguages,
                   supportedLanguages: supportedLanguages)
        self.voiceSize = voiceSize
        self.gender = gender ?? .unspecified
        self.age = age

    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(primaryLanguages, forKey: .primaryLanguages)
        try container.encode(supportedLanguages, forKey: .supportedLanguages)
        try container.encode(voiceSize, forKey: .voiceSize)
        try container.encode(version, forKey: .version)
        try container.encode(gender.rawValue, forKey: .gender)
        try container.encode(age, forKey: .age)
    }
}
