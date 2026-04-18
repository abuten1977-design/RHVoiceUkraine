//
//  UkrainianVoicesApp.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
#if os(macOS)
import AppKit
import RHVoiceKit
#endif

@MainActor
#if os(macOS)
private final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var isSelfTestMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSelfTestMode else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Best-effort: if SwiftUI already created a window, bring it forward.
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isSelfTestMode else { return false }
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
#endif

// NOTE: Sentry SDK will be added after Distribution certificate is available.
// Requires re-signing of Sentry.framework for App Store Connect upload.

@main
struct UkrainianVoicesApp: App {
    private let isSelfTestMode = CommandLine.arguments.contains("--self-test")
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macAppDelegate
    #endif

    init() {
        #if os(macOS)
        macAppDelegate.isSelfTestMode = isSelfTestMode
        if isSelfTestMode {
            Task { @MainActor in
                await RHVoiceSelfTestRunner.runAndExit()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if isSelfTestMode {
                Text("Running RHVoice self-test…")
                    .padding()
            } else {
                ContentView()
            }
        }
    }
}
