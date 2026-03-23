//
//  MessageResponse.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 6/27/25.
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

public struct MessageResponse: Codable {
    public static let key: String = "respnse"
    let type: MessageType
    public let json: String?
    
    public init (type: MessageType, json: String? = nil) {
        self.type = type
        self.json = json
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case json
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = (try? container.decode(MessageType.self, forKey: .type)) ?? .unknown
        self.json = try? container.decode(String.self, forKey: .json)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let encodable = json {
            try container.encode(encodable, forKey: .json)
        } else {
            try container.encodeNil(forKey: .json)
        }
    }
}
