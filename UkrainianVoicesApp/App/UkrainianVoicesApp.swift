//
//  UkrainianVoicesApp.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
#if os(iOS)
import AVFoundation
import RHVoiceBridge
#elseif os(macOS)
import RHVoiceKit
#endif
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var isSelfTestMode = false
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isSelfTestMode else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Best-effort: if SwiftUI already created a window, bring it forward.
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if NSApp.windows.isEmpty {
                self.showFallbackWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isSelfTestMode else { return false }
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if NSApp.windows.isEmpty {
                    self.showFallbackWindow()
                }
            }
        }
        return false
    }

    private func showFallbackWindow() {
        if fallbackWindow == nil || fallbackWindow?.isVisible == false {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Українські голоси"
            window.contentViewController = NSHostingController(rootView: ContentView())
            window.center()
            fallbackWindow = window
        }
        fallbackWindow?.makeKeyAndOrderFront(nil)
    }
}
#endif

private enum RHVoiceVoiceRegistrationRefresher {
    private static let lastRegisteredBuildKey = "lastSpeechVoiceRegistrationBuild"

    static func refreshIfNeeded() {
        #if os(iOS)
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let defaults = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)
        guard defaults?.string(forKey: lastRegisteredBuildKey) != build else { return }

        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        defaults?.set(build, forKey: lastRegisteredBuildKey)
        defaults?.synchronize()
        #endif
    }
}

// NOTE: Sentry SDK will be added after Distribution certificate is available.
// Requires re-signing of Sentry.framework for App Store Connect upload.

@main
struct UkrainianVoicesApp: App {
    #if DEBUG
    private let isSelfTestMode = CommandLine.arguments.contains("--self-test")
    #else
    private let isSelfTestMode = false
    #endif
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macAppDelegate
    #endif

    init() {
        // Кеш завантажених голосів: щоб voiceCatalog бачив англійські голоси
        // і в процесі застосунку (головний список, preview).
        RHVoiceDownloadedVoicesCache.shared.start()
        RHVoiceVoiceRegistrationRefresher.refreshIfNeeded()
        #if os(iOS) && DEBUG
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        "APP_DIAG init build=\(version) bundle=\(Bundle.main.bundleIdentifier ?? "nil")".withCString {
            RHVoiceDebugLogString($0)
        }
        #endif
        #if os(macOS) && DEBUG
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
            #if DEBUG
            if isSelfTestMode {
                Text("Running RHVoice self-test…")
                    .padding()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
