//
//  UkrainianVoicesApp.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
import Sentry

@main
struct UkrainianVoicesApp: App {
    init() {
        // Initialize Sentry SDK for crash and hang detection
        SentrySDK.start { options in
            options.dsn = "INSERT_DSN_HERE" // Андрей добавит ключ позже
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0 // Отлавливаем зависания дольше 2 секунд
            options.enableCaptureFailedRequests = true
            options.attachStacktrace = true
            options.enableCrashHandler = true
            options.enableAutoSessionTracking = true
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
