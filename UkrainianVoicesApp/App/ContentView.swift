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

private let voiceCatalog: [VoiceDefinition] = RHVoiceSharedSettings.voiceCatalog.map(VoiceDefinition.init)

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

    private let previewEngine = RHVoiceEngine()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isPlayerAttached = false

    func play(
        text: String,
        voiceName: String,
        rate: Double,
        volume: Double,
        pitch: Double = 1.0,
        onFinish: @escaping @MainActor () -> Void
    ) throws {
        let requestStart = CFAbsoluteTimeGetCurrent()
        #if os(iOS)
        // Audio session must be active before local preview playback on iOS.
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        let synthStart = CFAbsoluteTimeGetCurrent()
        guard let buffer = previewEngine.synthesize(
            text,
            voice: voiceName,
            rate: rate,
            volume: volume,
            pitch: pitch
        ) else {
            throw PreviewError.synthesisFailed(voiceName)
        }
        let synthMs = Int(((CFAbsoluteTimeGetCurrent() - synthStart) * 1000).rounded())

        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()

        if !isPlayerAttached {
            audioEngine.attach(playerNode)
            isPlayerAttached = true
        }

        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: buffer.format)
        try audioEngine.start()

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) {
            DispatchQueue.main.async {
                onFinish()
            }
        }
        playerNode.play()
        let totalMs = Int(((CFAbsoluteTimeGetCurrent() - requestStart) * 1000).rounded())
        LogCollector.shared.log("Preview latency voice=\(voiceName) chars=\(text.count) synthMs=\(synthMs) totalToPlayMs=\(totalMs)")
    }

    func stop() {
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()
    }
}

@MainActor
private final class ContentViewModel: ObservableObject {
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

    private let playbackController = PreviewPlaybackController()

    init() {
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
        let storedEnabled = Set(snapshot.enabledVoiceIdentifiers)
        let effectiveEnabled = Self.normalizedEnabledVoices(storedEnabled)
        let storedSelected = snapshot.selectedVoiceIdentifier
        let initialRate = snapshot.generalSettings.rate
        let initialVolume = Self.clampBaselineMultiplier(snapshot.generalSettings.volume)
        let initialSpeedMultiplier = Self.clampSpeedMultiplier(snapshot.generalSettings.speedMultiplier)
        let initialSentencePause = snapshot.generalSettings.sentencePause
        let initialWordGap = Self.clampWordGap(snapshot.generalSettings.wordGap)
        let initialPitch = snapshot.generalSettings.pitch

        self.rate = 0.5
        self.volume = initialVolume
        self.speedMultiplier = initialSpeedMultiplier
        self.pitch = initialPitch
        self.sentencePause = initialSentencePause
        self.wordGap = initialWordGap
        self.testText = "Привіт! Це тест українського голосу."
        self.enabledVoiceIdentifiers = effectiveEnabled
        self.selectedVoiceIdentifier = storedSelected
        self.voiceSettingsByIdentifier = Dictionary(uniqueKeysWithValues: voiceCatalog.map { voice in
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
            return (voice.identifier, ContentViewModel.loadStoredSettings(for: voice.identifier, fallbackRate: initialRate, fallbackVolume: initialVolume, fallbackSpeedMultiplier: initialSpeedMultiplier, fallbackSentencePause: initialSentencePause, fallbackWordGap: initialWordGap, fallbackPitch: initialPitch))
        })

        normalizeSelection()
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

        do {
            try playbackController.play(
                text: text,
                voiceName: voiceName,
                rate: currentSettings.speedMultiplier,
                volume: 1.0,
                pitch: 1.0
            ) { [weak self] in
                guard let self else { return }
                self.isPreviewPlaying = false
                self.setStatus("Прослуховування завершено.")
            }
            isPreviewPlaying = true
            setStatus("Прослуховується голос \(voice.name).")
        } catch {
            isPreviewPlaying = false
            setStatus(error.localizedDescription)
        }
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
        let previousRevision = RHVoiceSharedSettingsStore.loadSnapshot().revision
        let snapshot = RHVoiceSharedSettingsSnapshot(
            schemaVersion: 1,
            revision: previousRevision + 1,
            updatedAt: Date(),
            voiceCatalog: RHVoiceSharedSettings.voiceCatalog,
            enabledVoiceIdentifiers: Array(enabledVoiceIdentifiers).sorted(),
            selectedVoiceIdentifier: selectedVoiceIdentifier,
            generalSettings: settings,
            perVoiceSettings: perVoice
        )

        do {
            try RHVoiceSharedSettingsStore.saveSnapshot(snapshot)
        } catch {
            setStatus("Не вдалося зберегти спільні налаштування: \(error.localizedDescription)")
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(voiceCatalog) { voice in
                        NavigationLink {
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
                        } label: {
                            voiceRow(voice)
                        }
                        .accessibilityLabel("\(voice.name), \(voice.languageTitle)")
                        .accessibilityValue(model.isEnabled(voice) ? "Доступний" : "Вимкнений")
                        .accessibilityHint("Відкрити налаштування голосу")
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
            }
            .navigationTitle("Українські голоси")
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
#endif
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
