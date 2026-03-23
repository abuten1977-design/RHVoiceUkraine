//
//  FileManager.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 16.09.2022.
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

private enum AppGroupDiagnosticsState {
    static let queue = DispatchQueue(label: "FileManager.AppGroupDiagnosticsState")
    static var loggedContexts: Set<String> = []
}

extension FileManager {
    
    private var sharedFolder: URL? {
        return containerURL(forSecurityApplicationGroupIdentifier: GeneratedConstants.applicationGroupIdentifier)
    }

    public var rhvoiceSupportedVoicesDataFileURL: URL? {
        return sharedFolder?.appendingPathComponent(Constants.SupportedVoicesDataFile)
    }
    
    public var rhvoiceDataPathURL: URL? {
        return sharedFolder?.appendingPathComponent(Constants.RHVoiceDataFolderName)
    }
    
    public var rhvoicePackagePathURL: URL? {
        return sharedFolder?.appendingPathComponent(Constants.RHVoicePackageFolderName)
    }
    
    public var rhvoiceConfigFolderPathURL: URL? {
        return sharedFolder?.appendingPathComponent(Constants.RHVoiceConfigFolderName)
    }
    
    public var rhvoiceConfigPathURL: URL? {
        return rhvoiceConfigFolderPathURL?.appendingPathComponent(Constants.RHVoiceConfigFileName)
    }
    
    public var documentsDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    public var rhvoiceDataPathURLInDocuments: URL {
        return documentsDirectoryURL
            .appendingPathComponent(Constants.RHVoiceDataFolderName)
    }
    
    public static func voicesFolder(_ dataFolder: URL) -> URL {
        return dataFolder.appendingPathComponent("voices")
    }
    
    public static func languagesFolder(_ dataFolder: URL) -> URL {
        return dataFolder.appendingPathComponent("languages")
    }

    @discardableResult
    public func verifyRHVoiceAppGroup(context: String) -> Bool {
        let groupID = GeneratedConstants.applicationGroupIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let shouldLog = AppGroupDiagnosticsState.queue.sync {
            AppGroupDiagnosticsState.loggedContexts.insert(context).inserted
        }

        guard let containerURL = containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            if shouldLog {
                Log.error("App group is unavailable. Context: \(context). Bundle: \(bundleID). Group: \(groupID).")
            }
            return false
        }

        let probeFolder = containerURL.appendingPathComponent(".rhvoice-ee-diagnostics", isDirectory: true)
        let probeFile = probeFolder.appendingPathComponent("probe-\(UUID().uuidString).tmp")

        do {
            try createDirectory(at: probeFolder, withIntermediateDirectories: true)
            try Data("probe".utf8).write(to: probeFile, options: [.atomic, .noFileProtection])
            try removeItem(at: probeFile)
            if shouldLog {
                Log.info("App group is available. Context: \(context). Bundle: \(bundleID). Group: \(groupID). Container: \(containerURL.path(percentEncoded: false))")
            }
            return true
        } catch {
            if shouldLog {
                Log.error("App group container is not writable. Context: \(context). Bundle: \(bundleID). Group: \(groupID). Container: \(containerURL.path(percentEncoded: false)). Error: \(error)")
            }
            return false
        }
    }
}
