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
}
