//
//  LogCollector.swift
//  Ukrainian Voices for VoiceOver
//

import Foundation
#if os(iOS)
import MessageUI
#endif
import SwiftUI

class LogCollector: NSObject, MFMailComposeViewControllerDelegate {
    static let shared = LogCollector()
    
    private var logs: [String] = []
    private let queue = DispatchQueue(label: "com.rhvoice.logcollector")
    
    func log(_ message: String) {
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            self.logs.append("[\(timestamp)] \(message)")
            // Keep only last 1000 logs
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
    
    func mailComposeController(_ controller: MFMailComposeViewController, 
                              didFinishWith result: MFMailComposeResult, 
                              error: Error?) {
        controller.dismiss(animated: true)
    }
}

struct MailView: UIViewControllerRepresentable {
    let logs: String
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(["support@rhvoice.com"])
        vc.setSubject("RHVoice Debug Logs - \(Date())")
        vc.setMessageBody(logs, isHTML: false)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailView
        
        init(_ parent: MailView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController,
                                  didFinishWith result: MFMailComposeResult,
                                  error: Error?) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
