//
//  Package.swift
//  rhvoice-ee
//
//  Created by Ihor Shevchuk on 14.09.2022.
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

public struct Package: Decodable {
    public let languages: [Language]
    let products: [PackageProduct]
    
    enum CodingKeys: CodingKey {
        case languages
        case products
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.languages = try container.decode([Language]?.self, forKey: .languages) ?? []
        self.products = (try? container.decode([PackageProduct]?.self, forKey: .products)) ?? []
    }
}

extension Package {
    init?(json: String?) {
        guard let json else {
            return nil
        }
        guard let jsonData = json.data(using: .utf8) else {
            Log.error("Error happened during converting JSON string to data.")
            return nil
        }
        
        do {
            self = try JSONDecoder().decode(Package.self, from: jsonData)
        } catch {
            Log.error("Error happened during parsing languages JSON. Error: \(error)")
            return nil
        }
    }
}
