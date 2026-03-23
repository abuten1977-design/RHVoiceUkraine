//
//  RHFileBacked.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 6/28/25.
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

@propertyWrapper
public struct FileBacked<Value: Codable> {
    private let urlProvider: () -> URL?
    private let makeUnprotected: Bool
    private let defaultValue: Value
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(
        default defaultValue: @autoclosure @escaping () -> Value,
        urlProvider: @escaping () -> URL?,
        makeUnprotected: Bool = false
    ) {
        self.urlProvider      = urlProvider
        self.makeUnprotected  = makeUnprotected
        self.defaultValue     = defaultValue()
    }
    
    public var wrappedValue: Value {
        get {
            load() ?? defaultValue
        }
        set {
            save(newValue)
        }
    }
}

// MARK: – Persistence helpers
private extension FileBacked {
    func load() -> Value? {
        guard let url = urlProvider() else {
            Log.error("Path to data file is nil. Returning default.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
            return try decoder.decode(Value.self, from: data)
        } catch {
            Log.error("Failed to load \(Value.self) from \(url): \(error)")
            return nil
        }
    }
    
    func save(_ value: Value) {
        guard let url = urlProvider() else {
            Log.error("Path to data file is nil. Skipping save.")
            return
        }
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
            if makeUnprotected {
                var attr = try FileManager.default.attributesOfItem(atPath: url.path)
                if attr[.protectionKey] as? String != FileProtectionType.none.rawValue {
                    attr[.protectionKey] = FileProtectionType.none.rawValue
                    try FileManager.default.setAttributes(attr, ofItemAtPath: url.path)
                }
            }
            Log.debug("Saved \(Value.self) (\(data.count) bytes) to \(url).")
        } catch {
            Log.error("Failed to save \(Value.self) to \(url): \(error)")
        }
    }
}
