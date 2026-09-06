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
            sentencePauseStrength: RHVoiceSpeechSettings.recommended.sentencePauseStrength,
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

// task-226 round 3, ФАКТ (ssml.hpp:345): break_handler defaults to
// break_phrase BEFORE reading the `strength` attribute, so build ≤225's
// `<break time='…ms'/>` (no `strength` attribute) already produced a real
// pause — only the requested duration was ignored. Migration therefore keys
// off the legacy VALUE, not just its presence: >0 kept a working pause and
// must migrate to `.medium`; exactly 0 had the pause switched off and stays
// `.none`. (Round 2 wrongly treated presence alone as "always .none" —
// fixed here.)
final class RHVoicePauseStrengthMigrationTests: XCTestCase {
    func testSsmlValueMapping() {
        XCTAssertNil(RHVoicePauseStrength.none.ssmlValue)
        XCTAssertEqual(RHVoicePauseStrength.medium.ssmlValue, "medium")
    }

    func testResolvedMigratesZeroLegacyMillisecondsToNone() {
        let suiteName = "com.rhvoice.tests.pause-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(0.0, forKey: "legacyMs")
        XCTAssertEqual(
            RHVoicePauseStrength.resolved(from: defaults, key: "strength", legacyMillisecondsKey: "legacyMs", fallback: .medium),
            .none
        )
    }

    func testResolvedMigratesPositiveLegacyMillisecondsToMedium() {
        let suiteName = "com.rhvoice.tests.pause-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(800.0, forKey: "legacyMs")
        XCTAssertEqual(
            RHVoicePauseStrength.resolved(from: defaults, key: "strength", legacyMillisecondsKey: "legacyMs", fallback: .medium),
            .medium
        )
    }

    func testResolvedUsesFallbackWhenNeitherKeyIsPresent() {
        let suiteName = "com.rhvoice.tests.pause-fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            RHVoicePauseStrength.resolved(from: defaults, key: "strength", legacyMillisecondsKey: "legacyMs", fallback: .medium),
            .medium
        )
    }

    // task-226 round 3: build ≤225's ACTUAL snapshot file (schemaVersion 1) has
    // no `sentencePauseStrength` key at all — this decode path, not just
    // `resolved(from:...)`, is what a real upgrading user's value migrates
    // through.
    func testDecodingSnapshotWithPositiveLegacyMillisecondKeyResolvesToMedium() throws {
        let json = """
        {"rate":0.5,"volume":1.0,"speedMultiplier":1.0,"sentencePause":800,"wordGap":0.0,"pitch":1.0}
        """
        let settings = try JSONDecoder().decode(RHVoiceSpeechSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.sentencePauseStrength, .medium)
    }

    func testDecodingSnapshotWithZeroLegacyMillisecondKeyResolvesToNone() throws {
        let json = """
        {"rate":0.5,"volume":1.0,"speedMultiplier":1.0,"sentencePause":0,"wordGap":0.0,"pitch":1.0}
        """
        let settings = try JSONDecoder().decode(RHVoiceSpeechSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.sentencePauseStrength, .none)
    }

    // Clean install (neither key present) must still default to `.none` — this
    // is not a migration case, nobody asked for a pause out of the box.
    func testDecodingSnapshotWithNeitherKeyResolvesToNone() throws {
        let json = """
        {"rate":0.5,"volume":1.0,"speedMultiplier":1.0,"wordGap":0.0,"pitch":1.0}
        """
        let settings = try JSONDecoder().decode(RHVoiceSpeechSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.sentencePauseStrength, .none)
    }

    // п.4 задачі: відкат на попередню збірку (≤225) читає `sentencePause` як
    // обов'язковий ключ — encode(to:) мусить далі його писати, хоч сам більше
    // його не читає.
    func testEncodingWritesLegacyMillisecondKeyForRollbackSafety() throws {
        let mediumSettings = RHVoiceSpeechSettings(rate: 0.5, volume: 1.0, speedMultiplier: 1.0, sentencePauseStrength: .medium, wordGap: 0.0, pitch: 1.0)
        let mediumData = try JSONEncoder().encode(mediumSettings)
        let mediumObject = try JSONSerialization.jsonObject(with: mediumData) as? [String: Any]
        XCTAssertEqual(mediumObject?["sentencePause"] as? Double, 200)

        let noneSettings = RHVoiceSpeechSettings(rate: 0.5, volume: 1.0, speedMultiplier: 1.0, sentencePauseStrength: .none, wordGap: 0.0, pitch: 1.0)
        let noneData = try JSONEncoder().encode(noneSettings)
        let noneObject = try JSONSerialization.jsonObject(with: noneData) as? [String: Any]
        XCTAssertEqual(noneObject?["sentencePause"] as? Double, 0)
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
