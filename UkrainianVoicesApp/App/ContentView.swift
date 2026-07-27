//
//  ContentView.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
import AVFoundation
#if os(iOS)
import RHVoiceBridge
#else
import RHVoiceKit
#endif
#if os(macOS)
import AppKit
#endif

private let appGroup = RHVoiceSharedSettings.appGroupID
private let defaults = UserDefaults(suiteName: appGroup) ?? .standard
private let enabledVoiceIdentifiersKey = RHVoiceSharedSettings.enabledVoiceIdentifiersKey
private let selectedVoiceIdentifierKey = RHVoiceSharedSettings.selectedVoiceIdentifierKey
private let defaultEnabledVoiceIdentifiers = RHVoiceSharedSettings.defaultEnabledVoiceIdentifiers
private let preferredLanguageOrder = ["Українська", "Англійська"]
private let donorDisclaimerText = "Додаток RHVoice Ukrainian розробляється ГО «Право вибору» за підтримки Акселераційної програми Act to Drive Change проєкту «Фенікс: Сила спільнот», що виконується Фондом Східна Європа коштом Європейського Союзу."
private let donorLogosAccessibilityLabel = "Логотипи донорів: Європейський Союз — Прямуємо разом, Фонд Східна Європа, Фенікс — Сила спільнот, Act to Drive Change."

private struct LicenseItem: Identifiable {
    let title: String
    let license: String
    let attribution: String
    let note: String
    let url: URL?

    var id: String { title }
}

private let licenseItems: [LicenseItem] = [
    .init(
        title: "RHVoice engine",
        license: "LGPL v2.1",
        attribution: "RHVoice project",
        note: "Core speech engine. MAGE/GPLv3 components are not built into this app.",
        url: URL(string: "https://github.com/RHVoice/RHVoice")
    ),
    .init(
        title: "Anatol",
        license: "LGPL v2.1",
        attribution: "Анатолій Подорожко",
        note: "Ukrainian voice data distributed unmodified.",
        url: URL(string: "https://github.com/RHVoice/RHVoice")
    ),
    .init(
        title: "Natalia",
        license: "LGPL v2.1",
        attribution: "Наталія Чехаль",
        note: "Ukrainian voice data distributed unmodified.",
        url: URL(string: "https://github.com/RHVoice/RHVoice")
    ),
    .init(
        title: "Marianna",
        license: "CC BY-ND 4.0",
        attribution: "Marianna Firtka",
        note: "Ukrainian voice data distributed unmodified.",
        url: URL(string: "https://creativecommons.org/licenses/by-nd/4.0/")
    ),
    .init(
        title: "Volodymyr",
        license: "CC BY-ND 4.0",
        attribution: "Володимир Беглов",
        note: "Ukrainian voice data distributed unmodified.",
        url: URL(string: "https://creativecommons.org/licenses/by-nd/4.0/")
    )
]

private struct SpeechComponentDiagnosticReport: Equatable {
    let summary: String
    let details: [String]
}

private struct VoiceDefinition: Identifiable, Hashable {
    let name: String
    let identifier: String
    let language: String
    let profileName: String
    let sampleText: String

    var id: String { identifier }

    var languageTitle: String {
        switch language {
        case "uk-UA": return "Українська"
        case "en-US": return "Англійська"
        default: return language
        }
    }

    init(_ descriptor: RHVoiceVoiceDescriptor) {
        self.name = descriptor.name
        self.identifier = descriptor.identifier
        self.language = descriptor.language
        self.profileName = descriptor.profileName
        self.sampleText = descriptor.sampleText
    }
}

private struct VoiceSettingsState: Equatable {
    var useCustomSettings = true
    var rate = 0.5
    var volume = 1.0
    var speedMultiplier = 1.0
    var sentencePause = 0.0
    var wordGap = 0.0
    var pitch = 1.0

    func withSpeedMultiplier(_ value: Double) -> VoiceSettingsState {
        var copy = self
        copy.speedMultiplier = value
        return copy
    }

    func neutralizedVoiceOverControlledSettings() -> VoiceSettingsState {
        var copy = self
        copy.rate = 0.5
        copy.volume = 1.0
        copy.pitch = 1.0
        return copy
    }
}

private struct AcceleratorPreset: Identifiable, Hashable {
    let title: String
    let multiplier: Double

    var id: Double { multiplier }
}

private let acceleratorPresets: [AcceleratorPreset] = [
    .init(title: "Повільно", multiplier: 0.8),
    .init(title: "Нормально", multiplier: 1.0),
    .init(title: "Трохи швидше", multiplier: 1.15),
    .init(title: "Швидко", multiplier: 1.3),
    .init(title: "Дуже швидко", multiplier: 1.5)
]

// Каталог голосів живе в ContentViewModel.voiceCatalog: він динамічний —
// завантажені голоси (напр. англійські) з'являються поруч з українськими
// одразу після download, без перезапуску застосунку.

@MainActor
private final class PreviewPlaybackController {
    enum PreviewError: LocalizedError {
        case synthesisFailed(String)

        var errorDescription: String? {
            switch self {
            case .synthesisFailed(let voiceName):
                return "Не вдалося синтезувати зразок для голосу \(voiceName)."
            }
        }
    }

    // Двигун створюється ЛІНИВО і ТІЛЬКИ на цій черзі: RHVoiceEngine init пише в
    // App-Group контейнер (RHVoiceConfig), що на macOS 26 може заблокуватись
    // назавжди — блокуватись має фоновий потік, а не вікно (task-082, частина 2:
    // раніше движок створювався в init моделі вікна і вішав застосунок, щойно
    // VoiceOver заходив у вікно).
    private let engineQueue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.preview-engine", qos: .userInitiated)
    private var previewEngine: RHVoiceEngine?
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlayerAttached = false

    func play(
        text: String,
        voiceName: String,
        rate: Double,
        volume: Double,
        pitch: Double = 1.0,
        onFinish: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        let requestStart = CFAbsoluteTimeGetCurrent()
        engineQueue.async { [weak self] in
            guard let self else { return }
            if self.previewEngine == nil {
                self.previewEngine = RHVoiceEngine()
            }
            let synthStart = CFAbsoluteTimeGetCurrent()
            guard let engine = self.previewEngine,
                  let buffer = engine.synthesize(
                      text,
                      voice: voiceName,
                      rate: rate,
                      volume: volume,
                      pitch: pitch
                  ) else {
                DispatchQueue.main.async { onError(PreviewError.synthesisFailed(voiceName)) }
                return
            }
            let synthMs = Int(((CFAbsoluteTimeGetCurrent() - synthStart) * 1000).rounded())

            DispatchQueue.main.async {
                do {
                    #if os(iOS)
                    // Audio session must be active before local preview playback on iOS.
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                    #endif

                    self.playerNode.stop()
                    self.audioEngine.stop()
                    self.audioEngine.reset()

                    if !self.isPlayerAttached {
                        self.audioEngine.attach(self.playerNode)
                        self.isPlayerAttached = true
                    }

                    self.audioEngine.connect(self.playerNode, to: self.audioEngine.mainMixerNode, format: buffer.format)
                    try self.audioEngine.start()

                    self.playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) {
                        DispatchQueue.main.async {
                            onFinish()
                        }
                    }
                    self.playerNode.play()
                    let totalMs = Int(((CFAbsoluteTimeGetCurrent() - requestStart) * 1000).rounded())
                    LogCollector.shared.log("Preview latency voice=\(voiceName) chars=\(text.count) synthMs=\(synthMs) totalToPlayMs=\(totalMs)")
                } catch {
                    onError(error)
                }
            }
        }
    }

    func stop() {
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()
    }
}

@MainActor
private final class ContentViewModel: ObservableObject {
    @Published var voiceCatalog: [VoiceDefinition]
    @Published var rate: Double
    @Published var volume: Double
    @Published var speedMultiplier: Double
    @Published var pitch: Double
    @Published var sentencePause: Double
    @Published var wordGap: Double
    @Published var testText: String
    @Published var enabledVoiceIdentifiers: Set<String>
    @Published var selectedVoiceIdentifier: String
    @Published var voiceSettingsByIdentifier: [String: VoiceSettingsState]
    @Published var editingVoice: VoiceDefinition?
    @Published var isPreviewPlaying = false
    @Published var statusMessage = ""
    @Published var isRunningSpeechComponentDiagnostics = false
    @Published var speechComponentDiagnosticReport: SpeechComponentDiagnosticReport?
    @Published var debugLogSize: Int = 0
    @Published var debugLogShareURL: URL?
    @Published var extendedDiagnosticsEnabled: Bool = false
    @Published var datesAsWordsEnabled: Bool = true
    @Published var timeAsWordsEnabled: Bool = true
    @Published var personalDictionaryEntries: [PersonalDictionaryEntry]
    @Published var personalDictionaryStatus: PersonalDictionaryFileStatus
    @Published var sharedStorageState: SharedStorageState = .loading

    enum SharedStorageState: Equatable {
        case loading
        case ready
        case unavailable
    }

    // App-Group disk IO must never run on the main thread: on macOS 26 an
    // unauthorized group container makes mkdirat/open block forever, freezing
    // the whole window (new-Mac launch hang, task-082).
    private static let storageQueue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.app-storage", qos: .userInitiated)

    private let playbackController = PreviewPlaybackController()

    init() {
        let general = RHVoiceSpeechSettings.recommended
        let initialCatalog = RHVoiceSharedSettings.builtInVoiceCatalog.map(VoiceDefinition.init)
        self.voiceCatalog = initialCatalog
        self.rate = 0.5
        self.volume = Self.clampBaselineMultiplier(general.volume)
        self.speedMultiplier = Self.clampSpeedMultiplier(general.speedMultiplier)
        self.pitch = general.pitch
        self.sentencePause = general.sentencePause
        self.wordGap = Self.clampWordGap(general.wordGap)
        self.testText = "Привіт! Це тест українського голосу."
        self.enabledVoiceIdentifiers = Self.normalizedEnabledVoices([])
        self.selectedVoiceIdentifier = RHVoiceSharedSettings.defaultVoiceIdentifier
        self.personalDictionaryEntries = []
        self.personalDictionaryStatus = PersonalDictionaryFileStatus(
            dictionaryPath: nil,
            metadataPath: nil,
            dictionaryExists: false,
            metadataExists: false,
            dictionarySize: 0,
            metadataSize: 0,
            dictionaryModifiedAt: nil,
            metadataModifiedAt: nil
        )
        self.voiceSettingsByIdentifier = Dictionary(uniqueKeysWithValues: initialCatalog.map { voice in
            (voice.identifier, VoiceSettingsState(
                useCustomSettings: true,
                rate: 0.5,
                volume: 1.0,
                speedMultiplier: Self.clampSpeedMultiplier(general.speedMultiplier),
                sentencePause: general.sentencePause,
                wordGap: Self.clampWordGap(general.wordGap),
                pitch: 1.0
            ))
        })

        bootstrapFromDisk()
        refreshVoiceCatalog()
        NotificationCenter.default.addObserver(
            forName: RHVoiceDownloadableVoices.inProcessListChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshVoiceCatalog()
        }
    }

    /// Перечитує каталог (вбудовані + завантажені) у фоні: диск App Group не можна
    /// чіпати на main (task-082). Нові завантажені голоси одразу вмикаються.
    func refreshVoiceCatalog() {
        Self.storageQueue.async { [weak self] in
            let downloaded = RHVoiceDownloadableVoices.scanInstalledVoices()
            let catalog = (RHVoiceSharedSettings.builtInVoiceCatalog + downloaded).map(VoiceDefinition.init)
            DispatchQueue.main.async {
                self?.applyRefreshedCatalog(catalog)
            }
        }
    }

    private func applyRefreshedCatalog(_ catalog: [VoiceDefinition]) {
        let previousIds = Set(voiceCatalog.map(\.identifier))
        let newIds = Set(catalog.map(\.identifier))
        guard previousIds != newIds else { return }
        voiceCatalog = catalog

        var stateChanged = false
        for voice in catalog where !previousIds.contains(voice.identifier) {
            // Щойно завантажений голос одразу доступний, як і вбудовані.
            if !enabledVoiceIdentifiers.contains(voice.identifier) {
                enabledVoiceIdentifiers.insert(voice.identifier)
                stateChanged = true
            }
            if voiceSettingsByIdentifier[voice.identifier] == nil {
                voiceSettingsByIdentifier[voice.identifier] = Self.loadStoredSettings(
                    for: voice.identifier,
                    fallbackRate: rate,
                    fallbackVolume: volume,
                    fallbackSpeedMultiplier: speedMultiplier,
                    fallbackSentencePause: sentencePause,
                    fallbackWordGap: wordGap,
                    fallbackPitch: pitch
                )
            }
        }
        let removedEnabled = enabledVoiceIdentifiers.filter { !newIds.contains($0) }
        if !removedEnabled.isEmpty {
            enabledVoiceIdentifiers.subtract(removedEnabled)
            stateChanged = true
        }
        normalizeSelection()
        if stateChanged, sharedStorageState == .ready {
            persistVoiceState()
            AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        }
    }

    private func bootstrapFromDisk() {
        Self.storageQueue.async { [weak self] in
            RHVoiceMacAppGroupMigration.migrateIfNeeded { message in
                LogCollector.shared.log(message)
            }
            let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
            let entries = PersonalUserDictionary.loadEntries()
            let status = PersonalUserDictionary.fileStatus()
            let logSize = DebugLogShareHelper.logSize()
            let shareURL = DebugLogShareHelper.logExists() ? DebugLogShareHelper.logURL : nil
            DispatchQueue.main.async {
                self?.applyLoadedState(snapshot: snapshot, entries: entries, status: status, logSize: logSize, shareURL: shareURL)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.sharedStorageState == .loading else { return }
            self.sharedStorageState = .unavailable
            self.setStatus("Спільне сховище недоступне: налаштування і словник тимчасово не зберігаються. Голоси працюють.")
        }
    }

    private func applyLoadedState(
        snapshot: RHVoiceSharedSettingsSnapshot,
        entries: [PersonalDictionaryEntry],
        status: PersonalDictionaryFileStatus,
        logSize: Int,
        shareURL: URL?
    ) {
        let storedEnabled = Set(snapshot.enabledVoiceIdentifiers)
        let initialRate = snapshot.generalSettings.rate
        let initialVolume = Self.clampBaselineMultiplier(snapshot.generalSettings.volume)
        let initialSpeedMultiplier = Self.clampSpeedMultiplier(snapshot.generalSettings.speedMultiplier)
        let initialSentencePause = snapshot.generalSettings.sentencePause
        let initialWordGap = Self.clampWordGap(snapshot.generalSettings.wordGap)

        enabledVoiceIdentifiers = Self.normalizedEnabledVoices(storedEnabled)
        selectedVoiceIdentifier = snapshot.selectedVoiceIdentifier
        volume = initialVolume
        speedMultiplier = initialSpeedMultiplier
        sentencePause = initialSentencePause
        wordGap = initialWordGap
        pitch = snapshot.generalSettings.pitch
        personalDictionaryEntries = entries
        personalDictionaryStatus = status
        debugLogSize = logSize
        debugLogShareURL = shareURL
        voiceSettingsByIdentifier = Dictionary(uniqueKeysWithValues: voiceCatalog.map { voice in
            if let stored = snapshot.perVoiceSettings[voice.identifier] {
                return (voice.identifier, VoiceSettingsState(
                    useCustomSettings: true,
                    rate: stored.settings.rate,
                    volume: 1.0,
                    speedMultiplier: Self.clampSpeedMultiplier(stored.settings.speedMultiplier),
                    sentencePause: stored.settings.sentencePause,
                    wordGap: Self.clampWordGap(stored.settings.wordGap),
                    pitch: 1.0
                ).neutralizedVoiceOverControlledSettings())
            }
            return (voice.identifier, ContentViewModel.loadStoredSettings(for: voice.identifier, fallbackRate: initialRate, fallbackVolume: initialVolume, fallbackSpeedMultiplier: initialSpeedMultiplier, fallbackSentencePause: initialSentencePause, fallbackWordGap: initialWordGap, fallbackPitch: snapshot.generalSettings.pitch))
        })

        normalizeSelection()
        sharedStorageState = .ready
        persistGeneralSettings()
        persistVoiceState()
    }

    var groupedVoices: [(String, [VoiceDefinition])] {
        Dictionary(grouping: voiceCatalog, by: { $0.languageTitle })
            .sorted { lhs, rhs in
                (preferredLanguageOrder.firstIndex(of: lhs.key) ?? preferredLanguageOrder.count) <
                (preferredLanguageOrder.firstIndex(of: rhs.key) ?? preferredLanguageOrder.count)
            }
    }

    var enabledVoices: [VoiceDefinition] {
        voiceCatalog.filter { enabledVoiceIdentifiers.contains($0.identifier) }
    }

    var selectedVoice: VoiceDefinition? {
        voiceCatalog.first(where: { $0.identifier == selectedVoiceIdentifier })
    }

    func enabledCount(for voices: [VoiceDefinition]) -> Int {
        voices.filter { enabledVoiceIdentifiers.contains($0.identifier) }.count
    }

    func isEnabled(_ voice: VoiceDefinition) -> Bool {
        enabledVoiceIdentifiers.contains(voice.identifier)
    }

    func settings(for voice: VoiceDefinition) -> VoiceSettingsState {
        voiceSettingsByIdentifier[voice.identifier] ??
            Self.loadStoredSettings(
                for: voice.identifier,
                fallbackRate: rate,
                fallbackVolume: volume,
                fallbackSpeedMultiplier: speedMultiplier,
                fallbackSentencePause: sentencePause,
                fallbackWordGap: wordGap,
                fallbackPitch: pitch
            )
    }

    func setVoiceEnabled(_ voice: VoiceDefinition, enabled: Bool) {
        if enabled {
            enabledVoiceIdentifiers.insert(voice.identifier)
            if enabledVoiceIdentifiers.count == 1 {
                selectedVoiceIdentifier = voice.identifier
            }
        } else {
            enabledVoiceIdentifiers.remove(voice.identifier)
            if selectedVoiceIdentifier == voice.identifier {
                selectedVoiceIdentifier = enabledVoices.first?.identifier ?? RHVoiceSharedSettings.defaultVoiceIdentifier
            }
        }
        persistVoiceState()
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        setStatus(enabled ? "Голос \(voice.name) доступний у системі." : "Голос \(voice.name) вимкнено.")
    }

    func selectVoiceForPreview(_ voice: VoiceDefinition) {
        if !isEnabled(voice) {
            enabledVoiceIdentifiers.insert(voice.identifier)
        }
        selectedVoiceIdentifier = voice.identifier
        persistVoiceState()
        setStatus("Голос \(voice.name) вибрано для прослуховування.")
    }

    func listenToSample(for voice: VoiceDefinition) {
        selectedVoiceIdentifier = voice.identifier
        persistVoiceState()
        previewVoice(voice, overrideText: voice.sampleText)
    }

    func previewSelectedVoice() {
        guard let voice = selectedVoice else {
            setStatus("Спочатку виберіть голос.")
            return
        }
        previewVoice(voice, overrideText: testText)
    }

    func previewDictionaryText(_ text: String) {
        guard let voice = selectedVoice ?? voiceCatalog.first else {
            setStatus("Спочатку виберіть голос.")
            return
        }
        previewVoice(voice, overrideText: text)
    }

    func reloadPersonalDictionary() {
        guard sharedStorageState == .ready else { return }
        Self.storageQueue.async { [weak self] in
            let entries = PersonalUserDictionary.loadEntries()
            let status = PersonalUserDictionary.fileStatus()
            DispatchQueue.main.async {
                self?.personalDictionaryEntries = entries
                self?.personalDictionaryStatus = status
            }
        }
    }

    func savePersonalDictionaryEntry(id: UUID?, displayWord: String, stressedWord: String) -> Bool {
        guard sharedStorageState == .ready else {
            setStatus(PersonalUserDictionaryError.appGroupUnavailable.localizedDescription)
            return false
        }
        do {
            if let id {
                try PersonalUserDictionary.updateEntry(id: id, displayWord: displayWord, stressedWord: stressedWord)
                setStatus("Запис словника оновлено.")
            } else {
                try PersonalUserDictionary.addEntry(displayWord: displayWord, stressedWord: stressedWord)
                setStatus("Запис додано до словника.")
            }
            reloadPersonalDictionary()
            return true
        } catch {
            setStatus(error.localizedDescription)
            return false
        }
    }

    func removePersonalDictionaryEntry(_ entry: PersonalDictionaryEntry) {
        guard sharedStorageState == .ready else {
            setStatus(PersonalUserDictionaryError.appGroupUnavailable.localizedDescription)
            return
        }
        do {
            try PersonalUserDictionary.removeEntry(id: entry.id)
            reloadPersonalDictionary()
            setStatus("Запис «\(entry.displayWord)» видалено зі словника.")
        } catch {
            setStatus(error.localizedDescription)
        }
    }

    func stopPreview() {
        playbackController.stop()
        isPreviewPlaying = false
        setStatus("Прослуховування зупинено.")
    }

    func applyVoicesToSystem() {
        persistVoiceState()
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        let message = enabledVoiceIdentifiers.isEmpty
            ? "Зараз немає доступних голосів RHVoice."
            : "Список системних голосів оновлено. Доступних голосів: \(enabledVoiceIdentifiers.count)."
        setStatus(message)
    }

    func resetToRecommendedVoices() {
        enabledVoiceIdentifiers = defaultEnabledVoiceIdentifiers
        selectedVoiceIdentifier = RHVoiceSharedSettings.defaultVoiceIdentifier
        persistVoiceState()
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        setStatus("Рекомендовані голоси відновлено: усі українські голоси.")
    }

    func runSpeechComponentDiagnostics() {
#if os(macOS)
        isRunningSpeechComponentDiagnostics = true
        speechComponentDiagnosticReport = nil
        setStatus("Запущено діагностику мовного компонента.")

        Task { @MainActor [weak self] in
            guard let self else { return }

            let flags = AudioComponentFlags([.sandboxSafe, .isV3AudioUnit]).rawValue
            let description = AudioComponentDescription(
                componentType: kAudioUnitType_SpeechSynthesizer,
                componentSubType: fourCharCode("rhvc"),
                componentManufacturer: fourCharCode("RHVo"),
                componentFlags: flags,
                componentFlagsMask: flags
            )

            let manager = AVAudioUnitComponentManager.shared()
            let components = manager.components(matching: description)
            var details = [String]()
            details.append("Query type=ausp subtype=rhvc manufacturer=RHVo")
            details.append("Matching components: \(components.count)")

            if components.isEmpty {
                details.append("No speech synthesizer components matched the expected AudioComponentDescription.")
                finishSpeechComponentDiagnostics(
                    summary: "System did not return any RHVoice speech components.",
                    details: details
                )
                return
            }

            for component in components {
                let desc = component.audioComponentDescription
                details.append("Component: \(component.name)")
                details.append("  type=\(fourCharString(desc.componentType)) subtype=\(fourCharString(desc.componentSubType)) manufacturer=\(fourCharString(desc.componentManufacturer))")
                details.append("  flags=\(desc.componentFlags) mask=\(desc.componentFlagsMask)")

                do {
                    _ = try await AVAudioUnit.instantiate(
                        with: desc,
                        options: [.loadOutOfProcess]
                    )
                    details.append("  instantiate=OK")
                    finishSpeechComponentDiagnostics(
                        summary: "System found and instantiated the RHVoice speech component.",
                        details: details
                    )
                    return
                } catch {
                    let nsError = error as NSError
                    details.append("  instantiate=FAIL domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
                }
            }

            finishSpeechComponentDiagnostics(
                summary: "System found the RHVoice speech component, but instantiation failed.",
                details: details
            )
        }
#else
        setStatus("Діагностика мовного компонента доступна лише на macOS.")
#endif
    }

    func refreshDebugLogState() {
        Self.storageQueue.async { [weak self] in
            let size = DebugLogShareHelper.logSize()
            let shareURL = DebugLogShareHelper.logExists() ? DebugLogShareHelper.logURL : nil
            let extendedEnabled = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?
                .bool(forKey: RHVoiceSharedSettings.extendedDiagnosticsKey) ?? false
            let defaults = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)
            let datesAsWords = defaults?.object(forKey: RHVoiceSharedSettings.datesAsWordsKey) == nil
                ? true
                : (defaults?.bool(forKey: RHVoiceSharedSettings.datesAsWordsKey) ?? true)
            DispatchQueue.main.async {
                self?.debugLogSize = size
                self?.debugLogShareURL = shareURL
                self?.extendedDiagnosticsEnabled = extendedEnabled
                self?.datesAsWordsEnabled = datesAsWords
                self?.timeAsWordsEnabled = defaults?.object(forKey: RHVoiceSharedSettings.timeAsWordsKey) == nil
                    ? true : (defaults?.bool(forKey: RHVoiceSharedSettings.timeAsWordsKey) ?? true)
            }
        }
    }

    func setDatesAsWords(_ enabled: Bool) {
        datesAsWordsEnabled = enabled
        Self.storageQueue.async { [weak self] in
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?
                .set(enabled, forKey: RHVoiceSharedSettings.datesAsWordsKey)
            DispatchQueue.main.async {
                self?.setStatus(enabled
                    ? "Дати читаються словами."
                    : "Дати читаються цифрами.")
            }
        }
    }

    func setTimeAsWords(_ enabled: Bool) {
        timeAsWordsEnabled = enabled
        Self.storageQueue.async { [weak self] in
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?.set(enabled, forKey: RHVoiceSharedSettings.timeAsWordsKey)
            DispatchQueue.main.async {
                self?.setStatus(enabled ? "Час читається словами." : "Час читається без розгортання у слова.")
            }
        }
    }

    func setExtendedDiagnostics(_ enabled: Bool) {
        extendedDiagnosticsEnabled = enabled
        Self.storageQueue.async { [weak self] in
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?
                .set(enabled, forKey: RHVoiceSharedSettings.extendedDiagnosticsKey)
            DispatchQueue.main.async {
                self?.setStatus(enabled
                    ? "Розширену діагностику увімкнено: прочитаний текст записується в лог на цьому пристрої."
                    : "Розширену діагностику вимкнено.")
            }
        }
    }

    func clearDebugLog() {
        Self.storageQueue.async { [weak self] in
            DebugLogShareHelper.clearLog()
            let size = DebugLogShareHelper.logSize()
            let shareURL = DebugLogShareHelper.logExists() ? DebugLogShareHelper.logURL : nil
            DispatchQueue.main.async {
                self?.debugLogSize = size
                self?.debugLogShareURL = shareURL
                self?.setStatus("Лог очищено.")
            }
        }
    }

    func updateGeneralRate(_ value: Double) {
        rate = value
        persistGeneralSettings()
    }

    func updateGeneralVolume(_ value: Double) {
        volume = value
        persistGeneralSettings()
    }

    func updateGeneralSpeedMultiplier(_ value: Double) {
        speedMultiplier = Self.clampSpeedMultiplier(value)
        persistGeneralSettings()
    }

    func updateGeneralSentencePause(_ value: Double) {
        sentencePause = value
        persistGeneralSettings()
    }

    func updateGeneralWordGap(_ value: Double) {
        wordGap = Self.clampWordGap(value)
        persistGeneralSettings()
    }

    func updateSettings(_ settings: VoiceSettingsState, for identifier: String) {
        var normalizedSettings = settings
            .withSpeedMultiplier(Self.clampSpeedMultiplier(settings.speedMultiplier))
            .neutralizedVoiceOverControlledSettings()
        normalizedSettings.useCustomSettings = true
        normalizedSettings.volume = 1.0
        normalizedSettings.pitch = 1.0
        voiceSettingsByIdentifier[identifier] = normalizedSettings
        let prefix = voiceSettingsKeyPrefix(for: identifier)
        defaults.set(true, forKey: "\(prefix).useCustomSettings")
        defaults.set(normalizedSettings.rate, forKey: "\(prefix).rate")
        defaults.set(normalizedSettings.volume, forKey: "\(prefix).volume")
        defaults.set(normalizedSettings.speedMultiplier, forKey: "\(prefix).speedMultiplier")
        defaults.set(normalizedSettings.sentencePause, forKey: "\(prefix).sentencePause")
        defaults.set(Self.clampWordGap(normalizedSettings.wordGap), forKey: "\(prefix).wordGap")
        defaults.set(normalizedSettings.pitch, forKey: "\(prefix).pitch")
        persistSharedSnapshot()
    }

    private func previewVoice(_ voice: VoiceDefinition, overrideText: String? = nil) {
        let text = (overrideText?.isEmpty == false) ? overrideText! : voice.sampleText
        let currentSettings = settings(for: voice)
        let voiceName = voice.profileName

        LogCollector.shared.log("Preview request voice=\(voice.name) profile=\(voiceName) textLength=\(text.count)")

        isPreviewPlaying = true
        setStatus("Готую голос \(voice.name)…")
        playbackController.play(
            text: text,
            voiceName: voiceName,
            rate: currentSettings.speedMultiplier,
            volume: 1.0,
            pitch: 1.0,
            onFinish: { [weak self] in
                guard let self else { return }
                self.isPreviewPlaying = false
                self.setStatus("Прослуховування завершено.")
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.isPreviewPlaying = false
                self.setStatus(error.localizedDescription)
            }
        )
    }

    private func persistVoiceState() {
        defaults.set(Array(enabledVoiceIdentifiers).sorted(), forKey: enabledVoiceIdentifiersKey)
        defaults.set(selectedVoiceIdentifier, forKey: selectedVoiceIdentifierKey)
        persistSharedSnapshot()
    }

    private func persistGeneralSettings() {
        defaults.set(0.5, forKey: RHVoiceSharedSettings.rateKey)
        defaults.set(1.0, forKey: RHVoiceSharedSettings.volumeKey)
        defaults.set(Self.clampSpeedMultiplier(speedMultiplier), forKey: RHVoiceSharedSettings.speedMultiplierKey)
        defaults.set(sentencePause, forKey: RHVoiceSharedSettings.sentencePauseKey)
        defaults.set(Self.clampWordGap(wordGap), forKey: RHVoiceSharedSettings.wordGapKey)
        defaults.set(1.0, forKey: RHVoiceSharedSettings.pitchKey)
        persistSharedSnapshot()
    }

    private func normalizeSelection() {
        if !enabledVoiceIdentifiers.contains(selectedVoiceIdentifier) {
            selectedVoiceIdentifier = enabledVoices.first?.identifier ?? RHVoiceSharedSettings.defaultVoiceIdentifier
        }
    }

    private func setStatus(_ message: String) {
        statusMessage = message
        LogCollector.shared.log(message)
        announce(message)
    }

    private func finishSpeechComponentDiagnostics(summary: String, details: [String]) {
        isRunningSpeechComponentDiagnostics = false
        speechComponentDiagnosticReport = SpeechComponentDiagnosticReport(summary: summary, details: details)
        details.forEach { LogCollector.shared.log("Speech diagnostics: \($0)") }
        setStatus(summary)
    }

    private func persistSharedSnapshot() {
        // Не писати, поки фонове завантаження не підтвердило доступність сховища:
        // на несправному контейнері запис висне, а до .ready писати ще й нічого.
        guard sharedStorageState == .ready else { return }
        let settings = RHVoiceSpeechSettings(
            rate: 0.5,
            volume: 1.0,
            speedMultiplier: Self.clampSpeedMultiplier(speedMultiplier),
            sentencePause: sentencePause,
            wordGap: Self.clampWordGap(wordGap),
            pitch: 1.0
        )
        let perVoice = Dictionary(uniqueKeysWithValues: voiceCatalog.map { voice -> (String, RHVoicePerVoiceSettings) in
            let state = voiceSettingsByIdentifier[voice.identifier] ?? VoiceSettingsState(
                useCustomSettings: true,
                rate: 0.5,
                volume: 1.0,
                speedMultiplier: settings.speedMultiplier,
                sentencePause: settings.sentencePause,
                wordGap: settings.wordGap,
                pitch: 1.0
            )
            return (
                voice.identifier,
                RHVoicePerVoiceSettings(
                    useCustomSettings: true,
                    settings: RHVoiceSpeechSettings(
                        rate: 0.5,
                        volume: 1.0,
                        speedMultiplier: Self.clampSpeedMultiplier(state.speedMultiplier),
                        sentencePause: state.sentencePause,
                        wordGap: Self.clampWordGap(state.wordGap),
                        pitch: 1.0
                    )
                )
            )
        })
        let enabledSorted = Array(enabledVoiceIdentifiers).sorted()
        let selected = selectedVoiceIdentifier

        // Дискова частина (читання revision + запис) — у фоновій черзі: див. коментар
        // біля storageQueue. Значення зібрані на main вище.
        Self.storageQueue.async { [weak self] in
            let previousRevision = RHVoiceSharedSettingsStore.loadSnapshot().revision
            let snapshot = RHVoiceSharedSettingsSnapshot(
                schemaVersion: 1,
                revision: previousRevision + 1,
                updatedAt: Date(),
                voiceCatalog: RHVoiceSharedSettings.voiceCatalog,
                enabledVoiceIdentifiers: enabledSorted,
                selectedVoiceIdentifier: selected,
                generalSettings: settings,
                perVoiceSettings: perVoice
            )
            do {
                try RHVoiceSharedSettingsStore.saveSnapshot(snapshot)
            } catch {
                DispatchQueue.main.async {
                    self?.setStatus("Не вдалося зберегти спільні налаштування: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func loadStoredSettings(
        for identifier: String,
        fallbackRate: Double,
        fallbackVolume: Double,
        fallbackSpeedMultiplier: Double,
        fallbackSentencePause: Double,
        fallbackWordGap: Double,
        fallbackPitch: Double
    ) -> VoiceSettingsState {
        let prefix = voiceSettingsKeyPrefix(for: identifier)
        return VoiceSettingsState(
            useCustomSettings: true,
            rate: 0.5,
            volume: 1.0,
            speedMultiplier: Self.clampSpeedMultiplier(defaults.object(forKey: "\(prefix).speedMultiplier") as? Double ?? fallbackSpeedMultiplier),
            sentencePause: defaults.object(forKey: "\(prefix).sentencePause") as? Double ?? fallbackSentencePause,
            wordGap: Self.clampWordGap(defaults.object(forKey: "\(prefix).wordGap") as? Double ?? fallbackWordGap),
            pitch: 1.0
        )
    }

    private static func clampSpeedMultiplier(_ value: Double) -> Double {
        min(max(value, 0.8), 1.6)
    }

    private static func normalizedEnabledVoices(_ storedEnabled: Set<String>) -> Set<String> {
        let defaultOnly: Set<String> = [RHVoiceSharedSettings.defaultVoiceIdentifier]
        if storedEnabled.isEmpty || storedEnabled == defaultOnly {
            return defaultEnabledVoiceIdentifiers
        }
        return storedEnabled
    }

    private static func clampBaselineMultiplier(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }

    private static func clampWordGap(_ value: Double) -> Double {
        min(max(value, 0.0), 300.0)
    }

    private static func clampPitch(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}

private func fourCharString(_ code: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
}

struct ContentView: View {
    @StateObject private var model = ContentViewModel()
    @StateObject private var voiceDownloadManager = VoiceDownloadManager()

    private var voiceCatalog: [VoiceDefinition] { model.voiceCatalog }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    private var iosBody: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(voiceCatalog) { voice in
                        NavigationLink {
                            settingsScreen(for: voice)
                        } label: {
                            voiceRow(voice)
                        }
                        .accessibilityLabel("\(voice.name), \(voice.languageTitle)")
                        .accessibilityValue(model.isEnabled(voice) ? "Доступний" : "Вимкнений")
                        .accessibilityHint("Відкрити налаштування голосу")
                    }
                }

                Section {
                    personalDictionaryLink
                    downloadableLanguagesLink
                }

                readingSection

                Section("Довідка") {
                    howToLink
                    aboutLink
                    licensesLink
                }

                if model.sharedStorageState == .unavailable {
                    Section {
                        Text("Спільне сховище недоступне — зміни налаштувань і словника не зберігаються.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Увага: спільне сховище недоступне, зміни не зберігаються")
                    }
                }

                if !model.statusMessage.isEmpty {
                    Section {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Стан: \(model.statusMessage)")
                    }
                }

                diagnosticSection
            }
            .navigationTitle("Українські голоси")
            .onAppear {
                model.refreshDebugLogState()
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            model.refreshDebugLogState()
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
#endif
    }

    #if os(macOS)
    private var macBody: some View {
        NavigationStack {
            ScrollView {
                if model.sharedStorageState == .unavailable {
                    Text("Спільне сховище недоступне — зміни налаштувань і словника не зберігаються.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .accessibilityLabel("Увага: спільне сховище недоступне, зміни не зберігаються")
                }

                VStack(spacing: 0) {
                    ForEach(voiceCatalog) { voice in
                        NavigationLink {
                            settingsScreen(for: voice)
                        } label: {
                            voiceRow(voice)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(voice.name), \(voice.languageTitle)")
                        .accessibilityValue(model.isEnabled(voice) ? "Доступний" : "Вимкнений")
                        .accessibilityHint("Відкрити налаштування голосу")

                        if voice.id != voiceCatalog.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 8)

                Divider()

                personalDictionaryLink
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Divider()

                downloadableLanguagesLink
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Divider()

                VStack(spacing: 0) {
                    howToLink
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                    Divider()

                    aboutLink
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)

                    Divider()

                    licensesLink
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                Divider()

                readingSection
                    .padding(.horizontal, 12)

                Divider()

                diagnosticSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Українські голоси")
        }
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
    }
    #endif

    private func settingsScreen(for voice: VoiceDefinition) -> some View {
        VoiceSettingsScreen(
            voice: voice,
            settings: Binding(
                get: { model.settings(for: voice) },
                set: { model.updateSettings($0, for: voice.identifier) }
            ),
            isEnabled: Binding(
                get: { model.isEnabled(voice) },
                set: { model.setVoiceEnabled(voice, enabled: $0) }
            ),
            isPreviewPlaying: model.isPreviewPlaying,
            playSample: { model.listenToSample(for: voice) },
            stopPreview: { model.stopPreview() }
        )
    }

    private func voiceRow(_ voice: VoiceDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(voice.name)
                .font(.headline)
            Text(voice.languageTitle)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(model.isEnabled(voice) ? "Доступний" : "Вимкнений")
                .font(.caption)
                .foregroundColor(model.isEnabled(voice) ? .secondary : .orange)
        }
    }

    @ViewBuilder
    private var readingSection: some View {
        Section("Читання") {
            Toggle(isOn: Binding(
                get: { model.datesAsWordsEnabled },
                set: { model.setDatesAsWords($0) }
            )) {
                Label("Читати дати словами", systemImage: "calendar")
            }
            .accessibilityHint("Увімкнено: повні дати, як-от 10.07.2026, читаються словами — «десяте липня дві тисячі двадцять шостого року». Вимкнено: дати читаються цифрами.")

            Toggle(isOn: Binding(get: { model.timeAsWordsEnabled }, set: { model.setTimeAsWords($0) })) {
                Label("Читати час словами", systemImage: "clock")
            }
            .accessibilityHint("Увімкнено: 17:01 читається як час словами. Вимкнено: RHVoice не розгортає запис часу у години та хвилини.")

            Text("Стосується повних дат із чотиризначним роком. Короткі дати (10.07.26) завжди читаються цифрами.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var diagnosticSection: some View {
        Section("Діагностика") {
            Toggle(isOn: Binding(
                get: { model.extendedDiagnosticsEnabled },
                set: { model.setExtendedDiagnostics($0) }
            )) {
                Label("Розширена діагностика", systemImage: "stethoscope")
            }
            .accessibilityHint("Коли увімкнено, рушій записує прочитаний текст у лог-файл на цьому пристрої. Лог нікуди не надсилається автоматично — лише коли ви самі поділитесь ним.")

            Text("Щоб надіслати діагностику розробникам:\n1. Увімкни «Розширена діагностика».\n2. Тап «Очистити лог».\n3. Прочитай потрібні фрази через VoiceOver у будь-якій програмі.\n4. Повернись сюди і тап «Поділитись логом».\n5. У шторці обери Mail, Telegram або AirDrop і надішли лог.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .accessibilityLabel("Підказка щодо діагностики")

            Button {
                model.clearDebugLog()
            } label: {
                Label("Очистити лог", systemImage: "trash")
            }
            .accessibilityLabel("Очистити лог")
            .accessibilityHint("Стирає поточний лог-файл для нового вимірювання.")

            // Кеш із моделі, а не прямий виклик до контейнера: тіло view виконується
            // на main під час обходу VoiceOver, а containerURL/stat на macOS 26
            // може заблокуватись (task-082).
            if let url = model.debugLogShareURL {
                ShareLink(item: url) {
                    Label("Поділитись логом", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Поділитись логом")
                .accessibilityHint("Відкриває системне меню обміну для надсилання лог-файлу.")
            } else {
                Text("Лог ще порожній — спочатку прочитай щось через VoiceOver.")
                    .foregroundColor(.secondary)
            }

            Text("Розмір логу: \(model.debugLogSize) байт")
                .font(.footnote)
                .foregroundColor(.secondary)
                .accessibilityLabel("Розмір логу: \(model.debugLogSize) байт")
        }
    }

    private var personalDictionaryLink: some View {
        NavigationLink {
            PersonalDictionaryView(
                entries: model.personalDictionaryEntries,
                fileStatus: model.personalDictionaryStatus,
                isPreviewPlaying: model.isPreviewPlaying,
                reload: { model.reloadPersonalDictionary() },
                save: { id, displayWord, stressedWord in
                    model.savePersonalDictionaryEntry(
                        id: id,
                        displayWord: displayWord,
                        stressedWord: stressedWord
                    )
                },
                delete: { entry in model.removePersonalDictionaryEntry(entry) },
                preview: { text in model.previewDictionaryText(text) },
                stopPreview: { model.stopPreview() }
            )
        } label: {
            Label("Мій словник", systemImage: "book.closed")
        }
        .accessibilityLabel("Мій словник")
        .accessibilityHint("Відкрити особистий словник вимови.")
    }

    private var downloadableLanguagesLink: some View {
        NavigationLink {
            DownloadableLanguagesView(downloadManager: voiceDownloadManager)
        } label: {
            Label("Мови", systemImage: "globe")
        }
        .accessibilityLabel("Мови")
        .accessibilityHint("Українська вбудована; голоси інших мов можна завантажити.")
    }

    private var howToLink: some View {
        NavigationLink {
            VoiceOverHowToView()
        } label: {
            Label("Як увімкнути голос", systemImage: "checklist")
        }
        .accessibilityLabel("Як увімкнути голос")
        .accessibilityHint("Відкрити інструкцію для увімкнення українського голосу у VoiceOver.")
    }

    private var aboutLink: some View {
        NavigationLink {
            AboutAcknowledgementView()
        } label: {
            Label("Про застосунок", systemImage: "info.circle")
        }
        .accessibilityLabel("Про застосунок")
        .accessibilityHint("Відкрити інформацію про застосунок і підтримку проєкту.")
    }

    private var licensesLink: some View {
        NavigationLink {
            LicensesView()
        } label: {
            Label("Ліцензії", systemImage: "doc.text")
        }
        .accessibilityLabel("Ліцензії")
        .accessibilityHint("Відкрити ліцензії і атрибуцію RHVoice та голосів.")
    }
}

private struct PersonalDictionaryView: View {
    let entries: [PersonalDictionaryEntry]
    let fileStatus: PersonalDictionaryFileStatus
    let isPreviewPlaying: Bool
    let reload: () -> Void
    let save: (UUID?, String, String) -> Bool
    let delete: (PersonalDictionaryEntry) -> Void
    let preview: (String) -> Void
    let stopPreview: () -> Void

    @State private var editingEntry: PersonalDictionaryEntry?
    @State private var isAddingEntry = false
    @State private var showsTechnicalInfo = false
    @State private var entryPendingDeletion: PersonalDictionaryEntry?

    var body: some View {
        List {
            Section {
                DisclosureGroup("Технічна інформація", isExpanded: $showsTechnicalInfo) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileStatus.dictionaryExists ? "user_dictionary.txt: \(fileStatus.dictionarySize) байт" : "user_dictionary.txt: не створено")
                        Text(fileStatus.metadataExists ? "user_dictionary_meta.json: \(fileStatus.metadataSize) байт" : "user_dictionary_meta.json: не створено")
                            .foregroundColor(.secondary)
                        if let modifiedAt = fileStatus.dictionaryModifiedAt {
                            Text("Оновлено: \(modifiedAt.formatted(date: .numeric, time: .standard))")
                                .foregroundColor(.secondary)
                        }
#if os(macOS)
                        if let path = fileStatus.dictionaryPath {
                            Text(path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
#endif
                    }
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                }
                .accessibilityLabel("Технічна інформація")
                .accessibilityHint("Показує стан файлів особистого словника.")
            }

            if entries.isEmpty {
                Section {
                    Text("Словник порожній.")
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Особистий словник порожній")
                }
            } else {
                Section("Записи") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                editingEntry = entry
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.displayWord)
                                        .font(.headline)
                                    Text(entry.stressedWord)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.displayWord), вимова \(entry.stressedWord)")
                            .accessibilityHint("Відкрити редагування запису")

                            HStack {
                                Button {
                                    preview(entry.displayWord)
                                } label: {
                                    Label("Перевірити слово", systemImage: "speaker.wave.2")
                                }
                                .disabled(entry.displayWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityAddTraits(.startsMediaSession)
                                .accessibilityHint("Промовляє звичайне слово, щоб перевірити застосування словника.")

                                Button {
                                    preview(entry.stressedWord)
                                } label: {
                                    Label("Вимова", systemImage: "waveform")
                                }
                                .disabled(entry.stressedWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityAddTraits(.startsMediaSession)
                                .accessibilityHint("Промовляє введений варіант вимови напряму.")

                                Button(role: .destructive) {
                                    entryPendingDeletion = entry
                                } label: {
                                    Label("Видалити", systemImage: "trash")
                                }
                                .accessibilityLabel("Видалити \(entry.displayWord)")
                                .accessibilityHint("Відкриває підтвердження перед видаленням запису.")
                            }
                            .font(.caption)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                entryPendingDeletion = entry
                            } label: {
                                Label("Видалити", systemImage: "trash")
                            }
                            .accessibilityLabel("Видалити \(entry.displayWord)")
                        }
                    }
                    .onDelete { offsets in
                        entryPendingDeletion = offsets.map { entries[$0] }.first
                    }
                }
            }
        }
        .navigationTitle("Мій словник")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingEntry = true
                } label: {
                    Label("Додати", systemImage: "plus")
                }
                .accessibilityLabel("Додати запис")
                .accessibilityHint("Відкриває форму нового слова.")
            }
        }
        .sheet(isPresented: $isAddingEntry) {
            PersonalDictionaryEditorView(
                entry: nil,
                isPreviewPlaying: isPreviewPlaying,
                save: save,
                preview: preview,
                stopPreview: stopPreview
            )
        }
        .sheet(item: $editingEntry) { entry in
            PersonalDictionaryEditorView(
                entry: entry,
                isPreviewPlaying: isPreviewPlaying,
                save: save,
                preview: preview,
                stopPreview: stopPreview
            )
        }
        .onAppear(perform: reload)
        .confirmationDialog(
            entryPendingDeletion.map { "Видалити запис «\($0.displayWord)»?" } ?? "Видалити запис?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = entryPendingDeletion {
                Button("Видалити", role: .destructive) {
                    delete(entry)
                    entryPendingDeletion = nil
                }
            }
            Button("Скасувати", role: .cancel) {
                entryPendingDeletion = nil
            }
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
#endif
    }
}

private struct AboutAcknowledgementView: View {
    var body: some View {
        List {
            Section("Застосунок") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RHVoice Ukrainian")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(appVersionText)
                        .foregroundColor(.secondary)
                }
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
            }

            Section("Підтримка проєкту") {
                Text(donorDisclaimerText)
                    .textSelection(.enabled)
                    .accessibilityLabel(donorDisclaimerText)
            }

            Section("Логотипи партнерів") {
                DonorLogosBarView()
            }

            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Ліцензії та атрибуція", systemImage: "doc.text")
                }
                .accessibilityLabel("Ліцензії та атрибуція")
                .accessibilityHint("Відкрити список ліцензій і авторів голосів.")
            }
        }
        .navigationTitle("Про застосунок")
#if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
#endif
    }
}

private struct DonorLogosBarView: View {
    var body: some View {
        ZStack {
            Color.white
            Image("DonorLogosBar")
                .resizable()
                .scaledToFit()
                .padding(12)
                .accessibilityHidden(true)
        }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
#if os(macOS)
            .overlay {
                DonorLogosAccessibilityOverlay(label: donorLogosAccessibilityLabel)
            }
#else
            .accessibilityElement()
            .accessibilityLabel(donorLogosAccessibilityLabel)
            .accessibilityAddTraits(.isImage)
#endif
    }
}

#if os(macOS)
private struct DonorLogosAccessibilityOverlay: NSViewRepresentable {
    let label: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(label)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityLabel(label)
    }
}
#endif

private struct LicensesView: View {
    var body: some View {
        List {
            Section("Компоненти") {
                ForEach(licenseItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Ліцензія: \(item.license)")
                        Text("Атрибуція: \(item.attribution)")
                        Text(item.note)
                            .foregroundColor(.secondary)
                        if let url = item.url {
                            Link("Відкрити ліцензію або проєкт", destination: url)
                                .accessibilityLabel("Відкрити ліцензію для \(item.title)")
                                .accessibilityAddTraits(.isLink)
                        }
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("\(item.title). Ліцензія: \(item.license). Атрибуція: \(item.attribution). \(item.note)")
                }
            }

            Section("Команда голосів") {
                Text("Голоси створені в межах проєкту «Синтезатор української мови». Контакти: facebook.com/syntezator, vp88.mobile@gmail.com, rhvoice.su.")
                    .textSelection(.enabled)
            }

            Section("Повні тексти") {
                Text("Повні тексти ліцензій зберігаються у вихідному дереві RHVoice: RHVoiceCore/RHVoice/LICENSE.md та RHVoiceCore/RHVoice/licenses/.")
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Повні тексти ліцензій зберігаються у вихідному дереві RHVoice.")
            }
        }
        .navigationTitle("Ліцензії")
#if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
#endif
    }
}

private struct VoiceOverHowToView: View {
    var body: some View {
        List {
            Section("Перед початком") {
                Text("У головному списку застосунку переконайтесь, що потрібні голоси RHVoice позначені як доступні. Кнопка «Прослухати» у налаштуваннях кожного голосу дає швидку перевірку звучання.")
                    .textSelection(.enabled)
            }

            Section("iPhone або iPad") {
                NumberedInstructionList(items: [
                    "Відкрийте Налаштування.",
                    "Перейдіть до Універсальний доступ.",
                    "Відкрийте VoiceOver.",
                    "Відкрийте Мовлення.",
                    "Додайте або виберіть українську мову.",
                    "У списку голосів виберіть Anatol, Marianna, Natalia або Volodymyr."
                ])
            }

            Section("Mac") {
                NumberedInstructionList(items: [
                    "Відкрийте Системні параметри.",
                    "Перейдіть до Універсальний доступ.",
                    "Відкрийте VoiceOver.",
                    "Відкрийте налаштування голосу або мовлення VoiceOver.",
                    "Додайте українську мову або виберіть український голос.",
                    "Виберіть Anatol, Marianna, Natalia або Volodymyr."
                ])
            }

            Section("Якщо голос не з'явився") {
                Text("Поверніться до цього застосунку, увімкніть потрібний голос у списку і знову відкрийте налаштування VoiceOver. Після оновлення застосунку може знадобитися повторно вибрати голос у системних налаштуваннях.")
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Як увімкнути голос")
#if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
#endif
    }
}

private struct NumberedInstructionList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .fontWeight(.semibold)
                        .frame(width: 26, alignment: .trailing)
                        .accessibilityHidden(true)
                    Text(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Крок \(index + 1): \(item)")
            }
        }
        .textSelection(.enabled)
    }
}

private var appVersionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = info["CFBundleVersion"] as? String ?? "1"
    return "Версія \(version), збірка \(build)"
}

private struct PersonalDictionaryEditorView: View {
    let entry: PersonalDictionaryEntry?
    let isPreviewPlaying: Bool
    let save: (UUID?, String, String) -> Bool
    let preview: (String) -> Void
    let stopPreview: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayWord: String
    @State private var stressedWord: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case displayWord
        case stressedWord
    }

    init(
        entry: PersonalDictionaryEntry?,
        isPreviewPlaying: Bool,
        save: @escaping (UUID?, String, String) -> Bool,
        preview: @escaping (String) -> Void,
        stopPreview: @escaping () -> Void
    ) {
        self.entry = entry
        self.isPreviewPlaying = isPreviewPlaying
        self.save = save
        self.preview = preview
        self.stopPreview = stopPreview
        _displayWord = State(initialValue: entry?.displayWord ?? "")
        _stressedWord = State(initialValue: entry?.stressedWord ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Слово") {
                    TextField("", text: $displayWord, prompt: Text("наприклад: листопад"))
                        .focused($focusedField, equals: .displayWord)
                        .personalDictionaryTextInputSettings()
                        .accessibilityLabel("Слово як воно пишеться")
                        .accessibilityHint("Слово як пишеться.")
                    TextField("", text: $stressedWord, prompt: Text("наприклад: листоп+ад"))
                        .focused($focusedField, equals: .stressedWord)
                        .personalDictionaryTextInputSettings()
                        .accessibilityLabel("Вимова")
                        .accessibilityHint("Те саме слово зі знаком плюс перед наголошеною голосною, або інше слово чи фраза, як це читати.")
                    Text("Слово — як пишеться. Вимова — те саме слово зі знаком + перед наголошеною голосною, або інше слово чи фраза, як це читати.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Підказка: слово — як пишеться. Вимова — те саме слово зі знаком плюс перед наголошеною голосною, або інше слово чи фраза, як це читати.")
                }

                Section {
                    Button(isPreviewPlaying ? "Зупинити" : "Прослухати") {
                        isPreviewPlaying ? stopPreview() : preview(displayWord)
                    }
                    .disabled(displayWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityAddTraits(.startsMediaSession)
                    .accessibilityLabel(isPreviewPlaying ? "Зупинити прослуховування" : "Перевірити слово")
                    .accessibilityHint("Промовляє звичайне слово. Після збереження воно має звучати за словником.")
                }

#if os(macOS)
                Section("Дії") {
                    Button("Зберегти") {
                        saveAndDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Зберегти запис")

                    Button("Скасувати") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Скасувати")
                }
#endif
            }
            .navigationTitle(entry == nil ? "Нове слово" : "Редагування")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") {
                        dismiss()
                    }
                    .accessibilityLabel("Скасувати")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        saveAndDismiss()
                    }
                    .accessibilityLabel("Зберегти запис")
                }
            }
        }
        .onAppear {
            focusedField = .displayWord
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
#endif
    }

    private func saveAndDismiss() {
        if save(entry?.id, displayWord, stressedWord) {
            dismiss()
        }
    }
}

private extension View {
    func personalDictionaryTextInputSettings() -> some View {
#if os(iOS)
        self
            .autocorrectionDisabled(true)
            .textContentType(.none)
#else
        self
            .autocorrectionDisabled(true)
#endif
    }
}

private struct VoiceSettingsScreen: View {
    let voice: VoiceDefinition
    @Binding var settings: VoiceSettingsState
    @Binding var isEnabled: Bool
    let isPreviewPlaying: Bool
    let playSample: () -> Void
    let stopPreview: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Зробити голос доступним", isOn: $isEnabled)
                    .accessibilityLabel("Зробити голос \(voice.name) доступним")
                    .accessibilityValue(isEnabled ? "Увімкнено" : "Вимкнено")
                    .accessibilityHint("Керує доступністю цього голосу для VoiceOver.")
            }

            Section("Налаштування голосу") {
                Picker("Прискорювач", selection: acceleratorPresetBinding) {
                    ForEach(acceleratorPresets) { preset in
                        Text(preset.title).tag(preset.multiplier)
                    }
                }
                .accessibilityHint("Вибирає готовий множник темпу для голосу \(voice.name). Нормально не змінює системну швидкість VoiceOver.")

                sliderRow(
                    title: "Детальний множник",
                    value: settingBinding(\.speedMultiplier),
                    range: 0.8...1.6,
                    step: 0.05,
                    valueText: multiplierText(settings.speedMultiplier),
                    hint: "Точно налаштовує множник темпу для голосу \(voice.name). 1.0x не змінює системну швидкість VoiceOver."
                )

                sliderRow(
                    title: "Пауза між реченнями",
                    value: settingBinding(\.sentencePause),
                    range: 0...2000,
                    step: 100,
                    valueText: "\(Int(settings.sentencePause)) мс",
                    hint: "Змінює паузу між реченнями для голосу \(voice.name)."
                )

                sliderRow(
                    title: "Проміжок між словами",
                    value: settingBinding(\.wordGap),
                    range: 0...300,
                    step: 10,
                    valueText: "\(Int(settings.wordGap)) мс",
                    hint: "Додає проміжок між словами для голосу \(voice.name)."
                )
            }

            Section {
                Button(isPreviewPlaying ? "Зупинити" : "Прослухати") {
                    isPreviewPlaying ? stopPreview() : playSample()
                }
                .accessibilityAddTraits(.startsMediaSession)
                .accessibilityLabel(isPreviewPlaying ? "Зупинити прослуховування" : "Прослухати голос \(voice.name)")
                .accessibilityHint("Промовляє стандартну тестову фразу цим голосом.")
            }
        }
        .navigationTitle(voice.name)
#if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
#endif
    }

    private func settingBinding(_ keyPath: WritableKeyPath<VoiceSettingsState, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings.useCustomSettings = true
                settings[keyPath: keyPath] = newValue
            }
        )
    }

    private func baselinePercentBinding(_ keyPath: WritableKeyPath<VoiceSettingsState, Double>) -> Binding<Double> {
        Binding(
            get: { percentFromBaselineMultiplier(settings[keyPath: keyPath]) },
            set: { newPercent in
                settings.useCustomSettings = true
                settings[keyPath: keyPath] = baselineMultiplierFromPercent(newPercent)
            }
        )
    }

    private func baselinePercentText(_ value: Double) -> String {
        "\(Int(percentFromBaselineMultiplier(value).rounded()))%"
    }

    private var acceleratorPresetBinding: Binding<Double> {
        Binding(
            get: { nearestAcceleratorPreset(for: settings.speedMultiplier).multiplier },
            set: { newValue in
                settings.useCustomSettings = true
                settings.speedMultiplier = min(max(newValue, 0.8), 1.6)
            }
        )
    }

    private func multiplierText(_ value: Double) -> String {
        String(format: "%.2fx", min(max(value, 0.8), 1.6))
    }

    private func nearestAcceleratorPreset(for value: Double) -> AcceleratorPreset {
        acceleratorPresets.min { lhs, rhs in
            abs(lhs.multiplier - value) < abs(rhs.multiplier - value)
        } ?? acceleratorPresets[2]
    }

    private func percentFromBaselineMultiplier(_ value: Double) -> Double {
        let clamped = min(max(value, 0.5), 2.0)
        if clamped <= 1.0 {
            return min(max((clamped - 0.5) / 0.5 * 50.0, 0.0), 50.0)
        }
        return min(max(50.0 + (clamped - 1.0) * 50.0, 50.0), 100.0)
    }

    private func baselineMultiplierFromPercent(_ percent: Double) -> Double {
        let clamped = min(max(percent, 0.0), 100.0)
        if clamped <= 50.0 {
            return 0.5 + (clamped / 50.0) * 0.5
        }
        return 1.0 + ((clamped - 50.0) / 50.0)
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundColor(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityHint(hint)
        }
    }
}

private func voiceSettingsKeyPrefix(for identifier: String) -> String {
    "voiceSettings.\(identifier)"
}

private func announce(_ message: String) {
    #if os(macOS)
    let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
        .announcement: message,
        .priority: NSAccessibilityPriorityLevel.high.rawValue
    ]
    NSAccessibility.post(
        element: NSApp,
        notification: .announcementRequested,
        userInfo: userInfo
    )
    #elseif os(iOS)
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
}

#Preview {
    ContentView()
}
