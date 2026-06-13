import XCTest

final class RHVoiceSharedSettingsSnapshotCacheTests: XCTestCase {
    func testSnapshotUsesMemoryCacheWithoutCallingLoader() {
        var loaderCalls = 0
        let initial = Self.snapshot(revision: 10, speedMultiplier: 1.75)
        let loaded = Self.snapshot(revision: 11, speedMultiplier: 2.0)
        let cache = RHVoiceSharedSettingsSnapshotCache(
            notificationName: "com.rhvoice.tests.unused",
            initialSnapshot: initial,
            loader: {
                loaderCalls += 1
                return loaded
            }
        )

        XCTAssertEqual(cache.snapshot(), initial)
        XCTAssertEqual(loaderCalls, 0)
    }

    func testRefreshAsyncUpdatesCachedSnapshot() {
        let initial = Self.snapshot(revision: 20, speedMultiplier: 1.0)
        let loaded = Self.snapshot(revision: 21, speedMultiplier: 2.25)
        let cache = RHVoiceSharedSettingsSnapshotCache(
            queue: DispatchQueue(label: "com.rhvoice.tests.settings-cache"),
            notificationName: "com.rhvoice.tests.unused",
            initialSnapshot: initial,
            loader: { loaded }
        )

        cache.refreshAsync(reason: "unit-test")

        let deadline = Date().addingTimeInterval(2.0)
        while cache.snapshot() != loaded && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(cache.snapshot(), loaded)
    }

    func testDarwinNotificationRefreshesCachedSnapshot() {
        let notificationName = "com.rhvoice.tests.settingsChanged.\(UUID().uuidString)"
        let initial = Self.snapshot(revision: 30, speedMultiplier: 1.0)
        let updated = Self.snapshot(revision: 31, speedMultiplier: 1.6)
        let state = LockedSnapshot(initial)
        let cache = RHVoiceSharedSettingsSnapshotCache(
            queue: DispatchQueue(label: "com.rhvoice.tests.settings-cache-darwin"),
            notificationName: notificationName,
            initialSnapshot: initial,
            loader: { state.value }
        )

        cache.start()
        waitUntilSnapshot(cache, equals: initial)

        state.value = updated
        RHVoiceDarwinNotifications.post(notificationName)

        waitUntilSnapshot(cache, equals: updated)
        XCTAssertEqual(cache.snapshot().generalSettings.speedMultiplier, 1.6)
    }

    private static func snapshot(revision: Int, speedMultiplier: Double) -> RHVoiceSharedSettingsSnapshot {
        let settings = RHVoiceSpeechSettings(
            rate: RHVoiceSpeechSettings.recommended.rate,
            volume: RHVoiceSpeechSettings.recommended.volume,
            speedMultiplier: speedMultiplier,
            sentencePause: RHVoiceSpeechSettings.recommended.sentencePause,
            wordGap: RHVoiceSpeechSettings.recommended.wordGap,
            pitch: RHVoiceSpeechSettings.recommended.pitch
        )
        return RHVoiceSharedSettingsSnapshot(
            schemaVersion: 1,
            revision: revision,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(revision)),
            voiceCatalog: RHVoiceSharedSettings.voiceCatalog,
            enabledVoiceIdentifiers: Array(RHVoiceSharedSettings.defaultEnabledVoiceIdentifiers).sorted(),
            selectedVoiceIdentifier: RHVoiceSharedSettings.defaultVoiceIdentifier,
            generalSettings: settings,
            perVoiceSettings: Dictionary(
                uniqueKeysWithValues: RHVoiceSharedSettings.voiceCatalog.map {
                    ($0.identifier, RHVoicePerVoiceSettings.inherited(from: settings))
                }
            )
        )
    }

    private func waitUntilSnapshot(
        _ cache: RHVoiceSharedSettingsSnapshotCache,
        equals expected: RHVoiceSharedSettingsSnapshot,
        timeout: TimeInterval = 2.0
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while cache.snapshot() != expected && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

private final class LockedSnapshot {
    private let lock = NSLock()
    private var snapshot: RHVoiceSharedSettingsSnapshot

    init(_ snapshot: RHVoiceSharedSettingsSnapshot) {
        self.snapshot = snapshot
    }

    var value: RHVoiceSharedSettingsSnapshot {
        get {
            lock.lock()
            let value = snapshot
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            snapshot = newValue
            lock.unlock()
        }
    }
}
