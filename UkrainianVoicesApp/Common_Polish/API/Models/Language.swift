//
//  Language.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 12/29/24.
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

public final class Language: Decodable, Sendable {
    public let code: String
    public let testMessage: String
    public let name: String
    public let version: Version
    public var voices: [Voice] {
        return languageVoices ?? []
    }
    public let languageVoices: [Voice]?
    
    public let dataUrl: String
    public let dataMd5: String
    public let identifier: String
    
    private enum CodingKeys: String, CodingKey {
        case code = "lang2code"
        case testMessage
        case name
        case version
        case languageVoices = "voices"
        case dataUrl
        case dataMd5
        case identifier = "id"
    }

    init(code: String, testMessage: String, name: String, version: Version, voices: [Voice], dataUrl: String, dataMd5: String, identifier: String) {
        self.code = code
        self.testMessage = testMessage
        self.name = name
        self.version = version
        self.languageVoices = voices
        self.dataUrl = dataUrl
        self.dataMd5 = dataMd5
        self.identifier = identifier
    }
}
