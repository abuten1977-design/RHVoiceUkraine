//
//  DebugLogShareHelper.swift
//  Ukrainian Voices for VoiceOver
//

import Foundation

#if os(iOS)
import RHVoiceBridge
#else
import RHVoiceKit
#endif

enum DebugLogShareHelper {
    static let appGroupID = RHVoiceSharedSettings.appGroupID

    static var logURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("RHVoiceDebug.log")
    }

    static func clearLog() {
        RHVoiceDebugLogClear()
    }

    static func logExists() -> Bool {
        guard let path = logURL?.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    static func logSize() -> Int {
        guard let url = logURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.intValue
    }
}
