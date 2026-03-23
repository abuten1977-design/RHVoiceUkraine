//
//  SettingsItems.swift
//
//
//  Created by Ihor Shevchuk on 20.11.2022.
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
import RHVoice

public class SettingsItems: Codable {

    enum CodingKeys: String, CodingKey {
        case quality
        case languages
        case automaticUpdates
        case languageSwitching
        case voicesSettings
        case configRevision
    }

    var quality: RHSpeechUtteranceQuality = RHSpeechUtteranceQualityStandart
    var automaticUpdates = true
    var languageSwitching = true
    var configRevision = 0
    private var languageSettings: [String: LanguageSettings] = [:]
    private(set) var voicesSettings: [String: VoiceSettings] = [:]

    init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var quality = RHSpeechUtteranceQualityStandart
        if let qualityRaw = try? container.decode(Int.self, forKey: .quality) {
            quality = RHSpeechUtteranceQuality(rawValue: qualityRaw)
        }
        self.quality = quality

        self.languageSettings = (try? container.decode([String: LanguageSettings].self, forKey: .languages)) ?? [:]
        voicesSettings = (try? container.decode([String: VoiceSettings].self, forKey: .voicesSettings)) ?? [:]
        automaticUpdates = (try? container.decode(Bool.self, forKey: .automaticUpdates)) ?? true
        languageSwitching = (try? container.decode(Bool.self, forKey: .languageSwitching)) ?? true
        configRevision = (try? container.decode(Int.self, forKey: .configRevision)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(quality.rawValue, forKey: .quality)
        try container.encode(languageSettings, forKey: .languages)
        try container.encode(automaticUpdates, forKey: .automaticUpdates)
        try container.encode(languageSwitching, forKey: .languageSwitching)
        try container.encode(voicesSettings, forKey: .voicesSettings)
        try container.encode(configRevision, forKey: .configRevision)
    }

    func languageSettings(for code: String) -> LanguageSettings {
        guard let result = languageSettings[code] else {
            return LanguageSettings()
        }
        return result
    }

    func setLanguageSettings(for code: String, languageSettings: LanguageSettings) {
        self.languageSettings[code] = languageSettings
    }

    func voicesSettings(for voiceId: String) -> VoiceSettings {
        guard let result = voicesSettings[voiceId] else {
            return VoiceSettings(voiceID: voiceId)
        }
        return result
    }

    func setVoicesSettings(for voiceId: String, voiceSettings: VoiceSettings) {
        self.voicesSettings[voiceId] = voiceSettings
    }

    func removeVoicesSettings(for voiceId: String) {
        voicesSettings[voiceId] = nil
    }
}
