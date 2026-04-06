//
//  UkrainianVoicesApp.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
import Sentry

@main
struct UkrainianVoicesApp: App {
    init() {
        SentrySDK.start { options in
            options.dsn = "INSERT_DSN_HERE" // Андрей добавит ключ позже
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0
            options.attachStacktrace = true
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
