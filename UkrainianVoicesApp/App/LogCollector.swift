//
//  LogCollector.swift
//  Ukrainian Voices for VoiceOver
//

import Foundation
import SwiftUI

#if os(iOS)

class LogCollector: NSObject {
    static let shared = LogCollector()
    
    private var logs: [String] = []
    private let queue = DispatchQueue(label: "com.rhvoice.logcollector")
    
    func log(_ message: String) {
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            self.logs.append("[\(timestamp)] \(message)")
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
        }
    }
    
    func getAllLogs() -> String {
        queue.sync {
            return logs.joined(separator: "\n")
        }
    }
}

#else

// macOS stub
class LogCollector: NSObject {
    static let shared = LogCollector()
    private var logs: [String] = []
    private let queue = DispatchQueue(label: "com.rhvoice.logcollector")
    
    func log(_ message: String) {
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            self.logs.append("[\(timestamp)] \(message)")
        }
    }
    
    func getAllLogs() -> String {
        queue.sync { logs.joined(separator: "\n") }
    }
}

#endif
