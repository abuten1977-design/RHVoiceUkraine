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
#if os(iOS)
import MessageUI
#endif

#if os(macOS)
import AppKit
#endif

private let appGroup = RHVoiceSharedSettings.appGroupID
private let defaults = UserDefaults(suiteName: appGroup) ?? .standard
private let enabledVoiceIdentifiersKey = RHVoiceSharedSettings.enabledVoiceIdentifiersKey
private let selectedVoiceIdentifierKey = RHVoiceSharedSettings.selectedVoiceIdentifierKey
private let defaultEnabledVoiceIdentifiers = RHVoiceSharedSettings.defaultEnabledVoiceIdentifiers
private let preferredLanguageOrder = ["Ukrainian", "English"]

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
        case "uk-UA": return "Ukrainian"
        case "en-US": return "English"
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
    var useCustomSettings = false
    var rate = 0.5
    var volume = 1.0
    var speedMultiplier = 1.0
    var sentencePause = 0.0
    var pitch = 1.0
}

private let voiceCatalog: [VoiceDefinition] = RHVoiceSharedSettings.voiceCatalog.map(VoiceDefinition.init)

@MainActor
private final class PreviewPlaybackController {
    enum PreviewError: LocalizedError {
        case synthesisFailed(String)

        var errorDescription: String? {
            switch self {
            case .synthesisFailed(let voiceName):
                return "Could not synthesize sample for \(voiceName)."
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
        #if os(iOS)
        // Настройка audio session для iOS
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        guard let buffer = previewEngine.synthesize(
            text,
            voice: voiceName,
            rate: rate,
            volume: volume,
            pitch: pitch
        ) else {
            throw PreviewError.synthesisFailed(voiceName)
        }

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
        let storedSelected = snapshot.selectedVoiceIdentifier
        let initialRate = snapshot.generalSettings.rate
        let initialVolume = snapshot.generalSettings.volume
        let initialSpeedMultiplier = snapshot.generalSettings.speedMultiplier
        let initialSentencePause = snapshot.generalSettings.sentencePause

        self.rate = initialRate
        self.volume = initialVolume
        self.speedMultiplier = initialSpeedMultiplier
        self.pitch = 1.0
        self.sentencePause = initialSentencePause
        self.testText = "Привіт! Це тест українського голосу."
        self.enabledVoiceIdentifiers = storedEnabled.isEmpty ? defaultEnabledVoiceIdentifiers : storedEnabled
        self.selectedVoiceIdentifier = storedSelected
        self.voiceSettingsByIdentifier = Dictionary(uniqueKeysWithValues: voiceCatalog.map { voice in
            if let stored = snapshot.perVoiceSettings[voice.identifier] {
                return (voice.identifier, VoiceSettingsState(
                    useCustomSettings: stored.useCustomSettings,
                    rate: stored.settings.rate,
                    volume: stored.settings.volume,
                    speedMultiplier: stored.settings.speedMultiplier,
                    sentencePause: stored.settings.sentencePause
                ))
            }
            return (voice.identifier, ContentViewModel.loadStoredSettings(for: voice.identifier, fallbackRate: initialRate, fallbackVolume: initialVolume, fallbackSpeedMultiplier: initialSpeedMultiplier, fallbackSentencePause: initialSentencePause))
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
                fallbackSentencePause: sentencePause
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
    }

    func selectVoiceForPreview(_ voice: VoiceDefinition) {
        if !isEnabled(voice) {
            enabledVoiceIdentifiers.insert(voice.identifier)
        }
        selectedVoiceIdentifier = voice.identifier
        persistVoiceState()
        setStatus("Selected \(voice.name) for preview.")
    }

    func listenToSample(for voice: VoiceDefinition) {
        if !isEnabled(voice) {
            enabledVoiceIdentifiers.insert(voice.identifier)
            persistVoiceState()
            AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        }
        selectedVoiceIdentifier = voice.identifier
        persistVoiceState()
        previewVoice(voice, overrideText: voice.sampleText)
    }

    func previewSelectedVoice() {
        guard let voice = selectedVoice else {
            setStatus("Turn on and select a voice first.")
            return
        }
        previewVoice(voice, overrideText: testText)
    }

    func stopPreview() {
        playbackController.stop()
        isPreviewPlaying = false
        setStatus("Preview stopped.")
    }

    func applyVoicesToSystem() {
        persistVoiceState()
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        let message = enabledVoiceIdentifiers.isEmpty
            ? "No RHVoice voices are enabled right now."
            : "System voice list updated. Enabled voices: \(enabledVoiceIdentifiers.count)."
        setStatus(message)
    }

    func resetToRecommendedVoices() {
        enabledVoiceIdentifiers = defaultEnabledVoiceIdentifiers
        selectedVoiceIdentifier = RHVoiceSharedSettings.defaultVoiceIdentifier
        persistVoiceState()
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        setStatus("Recommended voices restored: Anatol.")
    }

    func runSpeechComponentDiagnostics() {
#if os(macOS)
        isRunningSpeechComponentDiagnostics = true
        speechComponentDiagnosticReport = nil
        setStatus("Running speech component diagnostics...")

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
        setStatus("Speech component diagnostics are available on macOS only.")
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
        speedMultiplier = value
        persistGeneralSettings()
    }

    func updateGeneralSentencePause(_ value: Double) {
        sentencePause = value
        persistGeneralSettings()
    }

    func updateSettings(_ settings: VoiceSettingsState, for identifier: String) {
        voiceSettingsByIdentifier[identifier] = settings
        let prefix = voiceSettingsKeyPrefix(for: identifier)
        defaults.set(settings.useCustomSettings, forKey: "\(prefix).useCustomSettings")
        defaults.set(settings.rate, forKey: "\(prefix).rate")
        defaults.set(settings.volume, forKey: "\(prefix).volume")
        defaults.set(settings.speedMultiplier, forKey: "\(prefix).speedMultiplier")
        defaults.set(settings.sentencePause, forKey: "\(prefix).sentencePause")
        persistSharedSnapshot()
    }

    private func previewVoice(_ voice: VoiceDefinition, overrideText: String? = nil) {
        let text = (overrideText?.isEmpty == false) ? overrideText! : voice.sampleText
        let currentSettings = settings(for: voice)
        let appliedRate = currentSettings.useCustomSettings ? currentSettings.rate : rate
        let appliedVolume = currentSettings.useCustomSettings ? currentSettings.volume : volume
        let appliedSpeedMultiplier = currentSettings.useCustomSettings ? currentSettings.speedMultiplier : speedMultiplier
        let voiceName = voice.profileName

        LogCollector.shared.log("Preview request voice=\(voice.name) profile=\(voiceName) textLength=\(text.count)")

        do {
            try playbackController.play(
                text: text,
                voiceName: voiceName,
                rate: appliedRate * appliedSpeedMultiplier,
                volume: appliedVolume
            ) { [weak self] in
                guard let self else { return }
                self.isPreviewPlaying = false
                self.setStatus("Preview finished.")
            }
            isPreviewPlaying = true
            setStatus("Previewing \(voice.name).")
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
        defaults.set(rate, forKey: RHVoiceSharedSettings.rateKey)
        defaults.set(volume, forKey: RHVoiceSharedSettings.volumeKey)
        defaults.set(speedMultiplier, forKey: RHVoiceSharedSettings.speedMultiplierKey)
        defaults.set(sentencePause, forKey: RHVoiceSharedSettings.sentencePauseKey)
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
            rate: rate,
            volume: volume,
            speedMultiplier: speedMultiplier,
            sentencePause: sentencePause,
            pitch: pitch
        )
        let perVoice = Dictionary(uniqueKeysWithValues: voiceCatalog.map { voice -> (String, RHVoicePerVoiceSettings) in
            let state = voiceSettingsByIdentifier[voice.identifier] ?? VoiceSettingsState(
                useCustomSettings: false,
                rate: settings.rate,
                volume: settings.volume,
                speedMultiplier: settings.speedMultiplier,
                sentencePause: settings.sentencePause
            )
            return (
                voice.identifier,
                RHVoicePerVoiceSettings(
                    useCustomSettings: state.useCustomSettings,
                    settings: RHVoiceSpeechSettings(
                        rate: state.rate,
                        volume: state.volume,
                        speedMultiplier: state.speedMultiplier,
                        sentencePause: state.sentencePause,
                        pitch: state.pitch
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
            setStatus("Could not save shared settings: \(error.localizedDescription)")
        }
    }

    private static func loadStoredSettings(
        for identifier: String,
        fallbackRate: Double,
        fallbackVolume: Double,
        fallbackSpeedMultiplier: Double,
        fallbackSentencePause: Double
    ) -> VoiceSettingsState {
        let prefix = voiceSettingsKeyPrefix(for: identifier)
        return VoiceSettingsState(
            useCustomSettings: defaults.object(forKey: "\(prefix).useCustomSettings") as? Bool ?? false,
            rate: defaults.object(forKey: "\(prefix).rate") as? Double ?? fallbackRate,
            volume: defaults.object(forKey: "\(prefix).volume") as? Double ?? fallbackVolume,
            speedMultiplier: defaults.object(forKey: "\(prefix).speedMultiplier") as? Double ?? fallbackSpeedMultiplier,
            sentencePause: defaults.object(forKey: "\(prefix).sentencePause") as? Double ?? fallbackSentencePause
        )
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
    @State private var showingMailComposer = false
    @StateObject private var model = ContentViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                overviewSection
#if os(macOS)
                diagnosticsSection
#endif
                voicesSection
                previewSection
                generalSettingsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
#if os(macOS)
        .frame(minWidth: 760, minHeight: 820)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
#endif
        .sheet(item: $model.editingVoice) { voice in
            VoiceSettingsSheet(
                voice: voice,
                settings: Binding(
                    get: { model.settings(for: voice) },
                    set: { model.updateSettings($0, for: voice.identifier) }
                )
            )
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ukrainian Voices")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Manage RHVoice voices, preview them locally, and apply the selected set to the system.")
                        .foregroundColor(.secondary)
                }
                Spacer()
                #if os(iOS)
                Button("Send Debug Logs") {
                    showingMailComposer = true
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Send debug logs via email")
                #endif
            }
        }
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showingMailComposer) {
            #if os(iOS)
            if MFMailComposeViewController.canSendMail() {
                MailView(logs: LogCollector.shared.getAllLogs())
            } else {
                VStack(spacing: 20) {
                    Text("Mail not configured")
                        .font(.headline)
                    Text("Please configure Mail app on your device to send debug logs.")
                        .multilineTextAlignment(.center)
                    Button("OK") {
                        showingMailComposer = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            #endif
        }
    }

    private var overviewSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to use")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Enable the voices you want, apply them to the system, then preview and adjust them.")
                    .foregroundColor(.secondary)

                LabeledContent("Enabled voices", value: "\(model.enabledVoiceIdentifiers.count)")
                LabeledContent("Current preview voice", value: model.selectedVoice?.name ?? "None")

                HStack(spacing: 12) {
                    Button("Apply enabled voices to system") {
                        model.applyVoicesToSystem()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Apply enabled voices to system")
                    .accessibilityValue("Apply \(model.enabledVoiceIdentifiers.count) voices")
                    .accessibilityHint("Updates the macOS voice list using the currently enabled RHVoice voices.")

                    Button("Reset to recommended voices") {
                        model.resetToRecommendedVoices()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Reset to recommended voices")
                    .accessibilityValue("Reset to Anatol")
                    .accessibilityHint("Turns on the recommended default voices and updates the system voice list.")
                }

                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Status: \(model.statusMessage)")
                }
            }
        }
    }

    private var voicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Available voices")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(model.groupedVoices, id: \.0) { language, voices in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(language)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(model.enabledCount(for: voices)) enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        ForEach(voices) { voice in
                            voiceCard(voice)
                        }
                    }
                }
            }
        }
    }

#if os(macOS)
    private var diagnosticsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Speech component diagnostics")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Checks whether macOS can find and instantiate the RHVoice speech component using the same Audio Unit lookup path as working reference apps.")
                    .foregroundColor(.secondary)

                Button(model.isRunningSpeechComponentDiagnostics ? "Running diagnostics..." : "Run speech component diagnostics") {
                    model.runSpeechComponentDiagnostics()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunningSpeechComponentDiagnostics)
                .accessibilityLabel("Run speech component diagnostics")
                .accessibilityHint("Finds the RHVoice speech component and tries to instantiate it.")

                if let report = model.speechComponentDiagnosticReport {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.summary)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(report.details.enumerated()), id: \.offset) { item in
                                    Text(item.element)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
#endif

    private var previewSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if model.enabledVoices.isEmpty {
                    Text("Turn on at least one voice in the Available voices section.")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Preview voice", selection: $model.selectedVoiceIdentifier) {
                        ForEach(model.enabledVoices) { voice in
                            Text("\(voice.name) (\(voice.languageTitle))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("Chooses which enabled voice is used for preview and custom text playback.")
                }

                TextField("Text to speak", text: $model.testText)
                    .accessibilityHint("Enter custom text for the selected preview voice.")

                HStack(spacing: 12) {
                    Button(model.isPreviewPlaying ? "Stop preview" : "Preview selected voice") {
                        model.isPreviewPlaying ? model.stopPreview() : model.previewSelectedVoice()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(.startsMediaSession)
                    .accessibilityLabel(model.isPreviewPlaying ? "Stop preview" : "Preview selected voice")
                    .accessibilityValue(model.isPreviewPlaying ? "Playing" : "Stopped")

                    Button("Use sample text for selected voice") {
                        if let selectedVoice = model.selectedVoice {
                            model.testText = selectedVoice.sampleText
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.selectedVoice == nil)
                }
            }
        }
    }

    private var generalSettingsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("General settings for all voices")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                sliderRow(
                    title: "Speech rate",
                    value: Binding(
                        get: { model.rate },
                        set: { model.updateGeneralRate($0) }
                    ),
                    range: 0...1,
                    step: 0.05,
                    valueText: String(format: "%.0f%%", model.rate * 100),
                    hint: "General speech rate"
                )

                sliderRow(
                    title: "Volume",
                    value: Binding(
                        get: { model.volume },
                        set: { model.updateGeneralVolume($0) }
                    ),
                    range: 0...1,
                    step: 0.05,
                    valueText: String(format: "%.0f%%", model.volume * 100),
                    hint: "General volume"
                )

                sliderRow(
                    title: "Speed multiplier",
                    value: Binding(
                        get: { model.speedMultiplier },
                        set: { model.updateGeneralSpeedMultiplier($0) }
                    ),
                    range: 1...5,
                    step: 0.5,
                    valueText: String(format: "%.1fx", model.speedMultiplier),
                    hint: "General speed multiplier"
                )

                sliderRow(
                    title: "Sentence pause",
                    value: Binding(
                        get: { model.sentencePause },
                        set: { model.updateGeneralSentencePause($0) }
                    ),
                    range: 0...2000,
                    step: 100,
                    valueText: "\(Int(model.sentencePause)) ms",
                    hint: "General sentence pause"
                )
            }
        }
    }

    private func voiceCard(_ voice: VoiceDefinition) -> some View {
        let isEnabled = model.isEnabled(voice)
        let isPreviewVoice = model.selectedVoiceIdentifier == voice.identifier
        let settings = model.settings(for: voice)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(voice.name)
                        .font(.headline)
                        .accessibilityLabel("\(voice.name), \(voice.languageTitle)\(isEnabled ? ", enabled" : ", disabled")\(isPreviewVoice ? ", current preview voice" : "")")
                    Text(voice.languageTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text(isEnabled ? "Enabled for system registration" : "Disabled")
                        .font(.caption)
                        .foregroundColor(isEnabled ? .secondary : .orange)
                        .accessibilityHidden(true)
                    if isPreviewVoice {
                        Text("Current preview voice")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                    if settings.useCustomSettings {
                        Text("Individual settings enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                Spacer()

                Toggle("Enable \(voice.name) voice", isOn: Binding(
                    get: { model.isEnabled(voice) },
                    set: { model.setVoiceEnabled(voice, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Enable \(voice.name) voice")
                .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Turns this voice on or off for system registration.")
            }

            HStack(spacing: 12) {
                Button("Use \(voice.name) for preview") {
                    model.selectVoiceForPreview(voice)
                }
                .buttonStyle(.bordered)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Use \(voice.name) for preview")
                .accessibilityHint("Sets this voice as the current preview voice")

                Button("Listen to \(voice.name) sample") {
                    model.listenToSample(for: voice)
                }
                .buttonStyle(.bordered)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Listen to \(voice.name) sample")
                .accessibilityHint("Plays a short sample of this voice")

                Button(settings.useCustomSettings ? "Open \(voice.name) settings, currently on" : "Open \(voice.name) settings") {
                    model.editingVoice = voice
                }
                .buttonStyle(.bordered)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open \(voice.name) settings")
                .accessibilityHint("Opens individual settings for this voice")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
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

            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityHint(hint)
        }
    }
}

private struct VoiceSettingsSheet: View {
    let voice: VoiceDefinition
    @Binding var settings: VoiceSettingsState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use individual settings for \(voice.name)", isOn: $settings.useCustomSettings)
                }

                Section("Voice settings") {
                    if settings.useCustomSettings {
                        sliderRow(title: "Speech rate", value: $settings.rate, range: 0...1, step: 0.05, valueText: String(format: "%.0f%%", settings.rate * 100))
                        sliderRow(title: "Volume", value: $settings.volume, range: 0...1, step: 0.05, valueText: String(format: "%.0f%%", settings.volume * 100))
                        sliderRow(title: "Speed multiplier", value: $settings.speedMultiplier, range: 1...5, step: 0.5, valueText: String(format: "%.1fx", settings.speedMultiplier))
                        sliderRow(title: "Sentence pause", value: $settings.sentencePause, range: 0...2000, step: 100, valueText: "\(Int(settings.sentencePause)) ms")
                    } else {
                        Text("This voice currently uses the general settings from the main screen.")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("\(voice.name) settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
#endif
    }

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
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
