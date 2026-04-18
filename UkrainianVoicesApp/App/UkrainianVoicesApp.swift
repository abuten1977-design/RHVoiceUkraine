//
//  UkrainianVoicesApp.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
#if os(macOS)
import AppKit
import RHVoiceKit
#endif

#if os(macOS)
private final class MainWindowController: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    var isSelfTestMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSelfTestMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.ensureMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isSelfTestMode else { return false }
        if !flag {
            ensureMainWindow()
        }
        return true
    }

    private func ensureMainWindow() {
        let existingWindow = NSApp.windows.first { candidate in
            candidate.canBecomeVisibleWithoutLogin && candidate.contentViewController != nil
        }

        if let existingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: ContentView())
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Ukrainian Voices"
        newWindow.setContentSize(NSSize(width: 980, height: 900))
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }
}
#endif

// NOTE: Sentry SDK will be added after Distribution certificate is available.
// Requires re-signing of Sentry.framework for App Store Connect upload.

@main
struct UkrainianVoicesApp: App {
    private let isSelfTestMode = CommandLine.arguments.contains("--self-test")
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MainWindowController.self) private var appDelegate
    #endif

    init() {
        #if os(macOS)
        appDelegate.isSelfTestMode = isSelfTestMode
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
