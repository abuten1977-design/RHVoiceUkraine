import Foundation

enum RHVoiceSharedSettings {
    static let appGroupID = "group.rhvoice.UkrainianVoices.shared"
    static let snapshotFileName = "SharedSettingsSnapshot.json"

    static let enabledVoiceIdentifiersKey = "enabledVoiceIdentifiers"
    static let selectedVoiceIdentifierKey = "selectedVoiceIdentifier"
    static let rateKey = "rate"
    static let volumeKey = "volume"
    static let speedMultiplierKey = "speedMultiplier"
    static let sentencePauseKey = "sentencePause"
    static let wordGapKey = "wordGap"
    static let pitchKey = "pitch"

    static let defaultVoiceIdentifier = "com.rhvoice.UkrainianVoices.anatol"
    static var defaultEnabledVoiceIdentifiers: Set<String> {
        Set(voiceCatalog.map(\.identifier))
    }

    static let voiceCatalog: [RHVoiceVoiceDescriptor] = [
        .init(name: "Anatol", identifier: "com.rhvoice.UkrainianVoices.anatol", language: "uk-UA", profileName: "Anatol", sampleText: "Привіт! Це тест голосу Анатол."),
        .init(name: "Marianna", identifier: "com.rhvoice.UkrainianVoices.marianna", language: "uk-UA", profileName: "Marianna", sampleText: "Привіт! Це тест голосу Маріанна."),
        .init(name: "Natalia", identifier: "com.rhvoice.UkrainianVoices.natalia", language: "uk-UA", profileName: "Natalia", sampleText: "Привіт! Це тест голосу Наталія."),
        .init(name: "Volodymyr", identifier: "com.rhvoice.UkrainianVoices.volodymyr", language: "uk-UA", profileName: "Volodymyr", sampleText: "Привіт! Це тест голосу Володимир.")
    ]
}

struct RHVoiceVoiceDescriptor: Codable, Hashable, Identifiable {
    let name: String
    let identifier: String
    let language: String
    let profileName: String
    let sampleText: String

    var id: String { identifier }
}

struct RHVoiceSpeechSettings: Codable, Equatable {
    var rate: Double
    var volume: Double
    var speedMultiplier: Double
    var sentencePause: Double
    var wordGap: Double
    var pitch: Double

    init(rate: Double, volume: Double, speedMultiplier: Double, sentencePause: Double, wordGap: Double, pitch: Double) {
        self.rate = rate
        self.volume = volume
        self.speedMultiplier = speedMultiplier
        self.sentencePause = sentencePause
        self.wordGap = wordGap
        self.pitch = pitch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rate            = try c.decode(Double.self, forKey: .rate)
        volume          = try c.decode(Double.self, forKey: .volume)
        speedMultiplier = try c.decode(Double.self, forKey: .speedMultiplier)
        sentencePause   = try c.decode(Double.self, forKey: .sentencePause)
        wordGap         = (try? c.decode(Double.self, forKey: .wordGap)) ?? 0.0
        pitch           = (try? c.decode(Double.self, forKey: .pitch)) ?? 1.0
    }

    static let recommended = RHVoiceSpeechSettings(
        rate: 0.5,
        volume: 1.0,
        speedMultiplier: 1.0,
        sentencePause: 0.0,
        wordGap: 0.0,
        pitch: 1.0
    )
}

struct RHVoicePerVoiceSettings: Codable, Equatable {
    var useCustomSettings: Bool
    var settings: RHVoiceSpeechSettings

    static func inherited(from settings: RHVoiceSpeechSettings) -> RHVoicePerVoiceSettings {
        RHVoicePerVoiceSettings(useCustomSettings: true, settings: settings)
    }
}

struct RHVoiceSharedSettingsSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var revision: Int
    var updatedAt: Date
    var voiceCatalog: [RHVoiceVoiceDescriptor]
    var enabledVoiceIdentifiers: [String]
    var selectedVoiceIdentifier: String
    var generalSettings: RHVoiceSpeechSettings
    var perVoiceSettings: [String: RHVoicePerVoiceSettings]

    static func initial() -> RHVoiceSharedSettingsSnapshot {
        let general = RHVoiceSpeechSettings.recommended
        return RHVoiceSharedSettingsSnapshot(
            schemaVersion: 1,
            revision: 1,
            updatedAt: Date(),
            voiceCatalog: RHVoiceSharedSettings.voiceCatalog,
            enabledVoiceIdentifiers: Array(RHVoiceSharedSettings.defaultEnabledVoiceIdentifiers).sorted(),
            selectedVoiceIdentifier: RHVoiceSharedSettings.defaultVoiceIdentifier,
            generalSettings: general,
            perVoiceSettings: Dictionary(
                uniqueKeysWithValues: RHVoiceSharedSettings.voiceCatalog.map {
                    ($0.identifier, RHVoicePerVoiceSettings.inherited(from: general))
                }
            )
        )
    }

    func effectiveSettings(for identifier: String) -> RHVoiceSpeechSettings {
        guard let override = perVoiceSettings[identifier], override.useCustomSettings else {
            return generalSettings
        }
        return override.settings
    }
}

enum RHVoiceSharedSettingsStore {
    static func loadSnapshot() -> RHVoiceSharedSettingsSnapshot {
        if let snapshot = loadSnapshotFromFile() {
            return snapshot
        }
        return loadSnapshotFromLegacyDefaults()
    }

    static func saveSnapshot(_ snapshot: RHVoiceSharedSettingsSnapshot) throws {
        let data = try JSONEncoder.rhvoiceEncoder.encode(snapshot)
        if let fileURL = snapshotFileURL() {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: fileURL, options: [.atomic])
        }

        // Keep old keys in sync during migration so existing extension/app builds still read the same values.
        if let defaults = sharedDefaults() {
            defaults.set(snapshot.enabledVoiceIdentifiers, forKey: RHVoiceSharedSettings.enabledVoiceIdentifiersKey)
            defaults.set(snapshot.selectedVoiceIdentifier, forKey: RHVoiceSharedSettings.selectedVoiceIdentifierKey)
            defaults.set(snapshot.generalSettings.rate, forKey: RHVoiceSharedSettings.rateKey)
            defaults.set(snapshot.generalSettings.volume, forKey: RHVoiceSharedSettings.volumeKey)
            defaults.set(snapshot.generalSettings.speedMultiplier, forKey: RHVoiceSharedSettings.speedMultiplierKey)
            defaults.set(snapshot.generalSettings.sentencePause, forKey: RHVoiceSharedSettings.sentencePauseKey)
            defaults.set(snapshot.generalSettings.wordGap, forKey: RHVoiceSharedSettings.wordGapKey)
            defaults.set(snapshot.generalSettings.pitch, forKey: RHVoiceSharedSettings.pitchKey)

            // Also save per-voice settings so extension can read them from UserDefaults fallback
            for (identifier, perVoice) in snapshot.perVoiceSettings {
                let prefix = "voiceSettings.\(identifier)"
                defaults.set(perVoice.useCustomSettings, forKey: "\(prefix).useCustomSettings")
                defaults.set(perVoice.settings.rate, forKey: "\(prefix).rate")
                defaults.set(perVoice.settings.volume, forKey: "\(prefix).volume")
                defaults.set(perVoice.settings.speedMultiplier, forKey: "\(prefix).speedMultiplier")
                defaults.set(perVoice.settings.sentencePause, forKey: "\(prefix).sentencePause")
                defaults.set(perVoice.settings.wordGap, forKey: "\(prefix).wordGap")
                defaults.set(perVoice.settings.pitch, forKey: "\(prefix).pitch")
            }
        }
    }

    private static func loadSnapshotFromFile() -> RHVoiceSharedSettingsSnapshot? {
        guard let fileURL = snapshotFileURL(),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder.rhvoiceDecoder.decode(RHVoiceSharedSettingsSnapshot.self, from: data)
    }

    private static func loadSnapshotFromLegacyDefaults() -> RHVoiceSharedSettingsSnapshot {
        let defaults = sharedDefaults()
        let general = RHVoiceSpeechSettings(
            rate: defaults?.object(forKey: RHVoiceSharedSettings.rateKey) as? Double ?? RHVoiceSpeechSettings.recommended.rate,
            volume: defaults?.object(forKey: RHVoiceSharedSettings.volumeKey) as? Double ?? RHVoiceSpeechSettings.recommended.volume,
            speedMultiplier: defaults?.object(forKey: RHVoiceSharedSettings.speedMultiplierKey) as? Double ?? RHVoiceSpeechSettings.recommended.speedMultiplier,
            sentencePause: defaults?.object(forKey: RHVoiceSharedSettings.sentencePauseKey) as? Double ?? RHVoiceSpeechSettings.recommended.sentencePause,
            wordGap: defaults?.object(forKey: RHVoiceSharedSettings.wordGapKey) as? Double ?? RHVoiceSpeechSettings.recommended.wordGap,
            pitch: defaults?.object(forKey: RHVoiceSharedSettings.pitchKey) as? Double ?? RHVoiceSpeechSettings.recommended.pitch
        )
        let enabled = defaults?.stringArray(forKey: RHVoiceSharedSettings.enabledVoiceIdentifiersKey)
            ?? Array(RHVoiceSharedSettings.defaultEnabledVoiceIdentifiers)
        let selected = defaults?.string(forKey: RHVoiceSharedSettings.selectedVoiceIdentifierKey)
            ?? RHVoiceSharedSettings.defaultVoiceIdentifier

        return RHVoiceSharedSettingsSnapshot(
            schemaVersion: 1,
            revision: 1,
            updatedAt: Date(),
            voiceCatalog: RHVoiceSharedSettings.voiceCatalog,
            enabledVoiceIdentifiers: enabled,
            selectedVoiceIdentifier: selected,
            generalSettings: general,
            perVoiceSettings: Dictionary(
                uniqueKeysWithValues: RHVoiceSharedSettings.voiceCatalog.map { descriptor in
                    let prefix = "voiceSettings.\(descriptor.identifier)"
                    let custom = defaults?.object(forKey: "\(prefix).useCustomSettings") as? Bool ?? true
                    let settings = RHVoiceSpeechSettings(
                        rate: defaults?.object(forKey: "\(prefix).rate") as? Double ?? general.rate,
                        volume: defaults?.object(forKey: "\(prefix).volume") as? Double ?? general.volume,
                        speedMultiplier: defaults?.object(forKey: "\(prefix).speedMultiplier") as? Double ?? general.speedMultiplier,
                        sentencePause: defaults?.object(forKey: "\(prefix).sentencePause") as? Double ?? general.sentencePause,
                        wordGap: defaults?.object(forKey: "\(prefix).wordGap") as? Double ?? general.wordGap,
                        pitch: defaults?.object(forKey: "\(prefix).pitch") as? Double ?? general.pitch
                    )
                    return (descriptor.identifier, RHVoicePerVoiceSettings(useCustomSettings: custom, settings: settings))
                }
            )
        )
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)
    }

    private static func snapshotFileURL() -> URL? {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)
        let url = containerURL?.appendingPathComponent(RHVoiceSharedSettings.snapshotFileName)
        NSLog("ðŸ“ SNAPSHOT URL: \(url?.path ?? "nil") (Group: \(RHVoiceSharedSettings.appGroupID))")
        return url
    }
}

final class RHVoiceSharedSettingsSnapshotCache {
    typealias SnapshotLoader = () -> RHVoiceSharedSettingsSnapshot

    private let queue: DispatchQueue
    private let lock = NSLock()
    private let loader: SnapshotLoader
    private let notificationName: String
    private var cachedSnapshot: RHVoiceSharedSettingsSnapshot
    private var observingDarwinNotifications = false

    init(
        queue: DispatchQueue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.shared-settings-cache", qos: .utility),
        notificationName: String = "com.rhvoice.UkrainianVoices.personalDictionaryChanged",
        initialSnapshot: RHVoiceSharedSettingsSnapshot = .initial(),
        loader: @escaping SnapshotLoader = RHVoiceSharedSettingsStore.loadSnapshot
    ) {
        self.queue = queue
        self.notificationName = notificationName
        self.cachedSnapshot = initialSnapshot
        self.loader = loader
    }

    deinit {
        if observingDarwinNotifications {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(notificationName as CFString),
                nil
            )
        }
    }

    func start() {
        startObservingDarwinNotifications()
        refreshAsync(reason: "startup")
    }

    func snapshot() -> RHVoiceSharedSettingsSnapshot {
        lock.lock()
        let snapshot = cachedSnapshot
        lock.unlock()
        return snapshot
    }

    func refreshAsync(reason: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.loader()
            self.lock.lock()
            self.cachedSnapshot = snapshot
            self.lock.unlock()
            NSLog("RHVoiceSharedSettingsSnapshotCache refreshed reason=\(reason) revision=\(snapshot.revision)")
        }
    }

    private func startObservingDarwinNotifications() {
        guard !observingDarwinNotifications else { return }
        observingDarwinNotifications = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.darwinNotificationCallback,
            notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static let darwinNotificationCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let cache = Unmanaged<RHVoiceSharedSettingsSnapshotCache>
            .fromOpaque(observer)
            .takeUnretainedValue()
        cache.refreshAsync(reason: "darwin")
    }
}

private extension JSONEncoder {
    static var rhvoiceEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var rhvoiceDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
