//
//  UkrainianVoicesApp.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
#if os(macOS)
import AppKit
import RHVoiceKit
#endif

// NOTE: Sentry SDK will be added after Distribution certificate is available.
// Requires re-signing of Sentry.framework for App Store Connect upload.

@main
struct UkrainianVoicesApp: App {
    init() {
        #if os(macOS)
        if CommandLine.arguments.contains("--self-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { @MainActor in
                await RHVoiceSelfTestRunner.runAndExit()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
