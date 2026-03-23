//
//  Message.swift
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

public struct Message: Codable {
    public static let key: String = "message"
    public let type: MessageType
    public let object: MessageHandler?
    
    enum CodingKeys: String, CodingKey {
        case type
        case object
    }
    
    public init (type: MessageType, object: MessageHandler? = nil) {
        self.type = type
        self.object = object
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = (try? container.decode(MessageType.self, forKey: .type)) ?? .unknown
        switch type {
        case .setVoices:
            object = try? container.decode(SetVoicesMessage.self, forKey: .object)
        case .getVoices:
            object = try? container.decode(GetVoicesMessage.self, forKey: .object)
        case .isSynthesizing:
            object = try? container.decode(IsSynthesizingMessage.self, forKey: .object)
        case .unknown:
            object = nil
            Log.error("Not valid Message type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let encodable = object {
            try container.encode(encodable, forKey: .object)
        } else {
            try container.encodeNil(forKey: .object)
        }
    }
}
