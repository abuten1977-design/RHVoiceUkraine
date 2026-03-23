//
//  Array+SynthesisVoice.swift
//  RHVoiceExtension
//
//  Created by Ihor Shevchuk on 30.11.2022.
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
import RHVoice

extension Array where Element == RHSpeechSynthesisVoice {
    public var rhAVVoices: [RHSpeechSynthesisProviderVoice] {
        return map { voice in
            return voice.avVoice
        }
    }
}

extension Array where Element == RHSpeechSynthesisProviderVoice {
    public var avVoices: [AVSpeechSynthesisProviderVoice] {
        return map { voice in
            let result = AVSpeechSynthesisProviderVoice(name: voice.name,
                                                        identifier: voice.identifier,
                                                        primaryLanguages: voice.primaryLanguages,
                                                        supportedLanguages: voice.supportedLanguages)
            result.age = voice.age
            result.version = voice.version
            result.gender = voice.gender
            return result
        }
    }
}

extension RHSpeechSynthesisVoice {
    public var avVoice: RHSpeechSynthesisProviderVoice {

        var languageCode = languageCode

        switch name.lowercased() {
        case "hana":
            languageCode = "sq-MK"
        default: break
        }

        let result = RHSpeechSynthesisProviderVoice(name: name,
                                                    identifier: identifier,
                                                    primaryLanguages: [languageCode],
                                                    supportedLanguages: [languageCode])
        result.gender = self.gender.avGender

        if let version = version?.string() {
            result.version = version
        }

        return result
    }
}
