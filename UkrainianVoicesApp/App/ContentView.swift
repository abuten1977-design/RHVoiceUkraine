//
//  ContentView.swift
//  Ukrainian Voices for VoiceOver
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
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
private let donorDisclaimerText = "Застосунок RHVoice UA розробляється громадською організацією «Харківський центр реабілітації молодих осіб з інвалідністю та членів їх сімей «Право вибору» за підтримки Акселераційної програми Act to Drive Change проєкту «Фенікс: Сила спільнот», що виконується Фондом Східна Європа коштом Європейського Союзу. Наповнення застосунку є відповідальністю ГО «Харківський центр реабілітації молодих осіб з інвалідністю та членів їх сімей «Право вибору» та необов’язково відображає позицію Фонду Східна Європа та ЄС."
private let donorLogosAccessibilityLabel = "Логотипи донорів: Європейський Союз — Прямуємо разом, Фонд Східна Європа, Фенікс — Сила спільнот, Act to Drive Change."

private struct LicenseItem: Identifiable {
    let title: String
    let license: String
    let attribution: String
    let note: String
    let url: URL?

    var id: String { title }
}

private let sourceCodeURL = URL(string: "https://github.com/abuten1977-design/RHVoiceUkraine")!

private let licenseItems: [LicenseItem] = [
    .init(
        title: "RHVoice UA (цей застосунок)",
        license: "GPL-3.0 або пізніша, з дозволом для App Store",
        attribution: "ГО «Право вибору»",
        note: "Вихідний код відкритий. Ви маєте право отримати повний код саме цієї збірки, змінювати його і поширювати далі на умовах GPL-3.",
        url: sourceCodeURL
    ),
    .init(
        title: "Рушій RHVoice",
        license: "GPL-3.0 або пізніша (частина файлів — LGPL-2.1)",
        attribution: "Ольга Яковлева",
        note: "Основний рушій синтезу. Розповсюдження через App Store дозволене окремим дозволом авторки від 3 серпня 2026 року.",
        url: URL(string: "https://github.com/RHVoice/RHVoice")
    ),
    .init(
        title: "hts_engine API",
        license: "3-clause BSD",
        attribution: "HTS Working Group, Nagoya Institute of Technology, Tokyo Institute of Technology",
        note: "Copyright (c) 2001-2015 Nagoya Institute of Technology; 2001-2008 Tokyo Institute of Technology. All rights reserved. Файли у складі RHVoice змінені авторкою рушія.",
        url: URL(string: "http://hts-engine.sourceforge.net/")
    ),
    .init(
        title: "sonic",
        license: "Apache-2.0",
        attribution: "Bill Cox",
        note: "Зміна темпу мовлення без спотворення голосу.",
        url: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")
    ),
    .init(
        title: "Boost, rapidxml, utf8cpp",
        license: "Boost Software License 1.0",
        attribution: "Boost contributors, Marcin Kalicinski, Nemanja Trifunovic",
        note: "Допоміжні бібліотеки у складі рушія.",
        url: URL(string: "https://www.boost.org/LICENSE_1_0.txt")
    ),
    .init(
        title: "ZIPFoundation",
        license: "MIT",
        attribution: "Thomas Zoechling",
        note: "Розпакування завантажених голосів.",
        url: URL(string: "https://github.com/weichsel/ZIPFoundation")
    ),
    .init(
        title: "Anatol",
        license: "LGPL-2.1",
        attribution: "Диктор Анатолій Подорожко; команда «Синтезатор української мови»: Artem Plaksin, Volodymyr Pyrih, Sergey Parshakov, Zvonimir Stanecic",
        note: "Український голос. Дані розповсюджуються без змін.",
        url: URL(string: "https://facebook.com/syntezator")
    ),
    .init(
        title: "Natalia",
        license: "LGPL-2.1",
        attribution: "Дикторка Наталія Чехаль; команда «Синтезатор української мови»: Artem Plaksin, Volodymyr Pyrih, Tomasz Bilecki, Zvonimir Stanecic",
        note: "Український голос. Дані розповсюджуються без змін.",
        url: URL(string: "https://facebook.com/syntezator")
    ),
    .init(
        title: "Marianna",
        license: "CC BY-ND 4.0",
        attribution: "Дикторка Marianna Firtka; команда «Синтезатор української мови»: Artem Plaksin, Volodymyr Pyrih, Maryna Herelyuk, Sergey Parshakov, Beka Gozalishvili",
        note: "Український голос. Дані розповсюджуються без змін (ліцензія забороняє похідні).",
        url: URL(string: "https://creativecommons.org/licenses/by-nd/4.0/")
    ),
    .init(
        title: "Volodymyr",
        license: "CC BY-ND 4.0",
        attribution: "Диктор Володимир Беглов; команда «Синтезатор української мови»",
        note: "Український голос. Дані розповсюджуються без змін (ліцензія забороняє похідні).",
        url: URL(string: "https://creativecommons.org/licenses/by-nd/4.0/")
    ),
    .init(
        title: "Англійські мовні дані (cmulex)",
        license: "CMU Pronouncing Dictionary",
        attribution: "Carnegie Mellon University",
        note: "Потрібні для читання латиниці українським голосом.",
        url: URL(string: "https://github.com/cmusphinx/cmudict")
    )
]

private let legalNoticeText = """
RHVoice UA. Copyright © 2026 ГО «Харківський центр реабілітації молодих осіб з інвалідністю та членів їх сімей «Право вибору».

Ця програма розповсюджується за GNU General Public License версії 3 або, на ваш вибір, будь-якої пізнішої версії, разом із додатковим дозволом на розповсюдження через Apple App Store.

Програма постачається БЕЗ ЖОДНИХ ГАРАНТІЙ, у тому числі без гарантій придатності для продажу чи для конкретної мети.

Ви маєте право поширювати копії цієї програми та змінювати її на умовах GPL-3. Ви також маєте право отримати повний вихідний код саме цієї збірки.
"""

private var buildIdentityText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = info["CFBundleVersion"] as? String ?? "?"
    return "Версія \(version), збірка \(build). Вихідний код цієї збірки позначено тегом build-\(build) у репозиторії проєкту."
}

/// Повні тексти ліцензій, що постачаються ВСЕРЕДИНІ застосунку (вимога GPL-3 §4:
/// копія ліцензії має супроводжувати програму, а не лежати лише в репозиторії).
private struct LicenseTextsView: View {
    /// Тексти можуть лежати або текою `LICENSES/`, або файлами в корені бандла —
    /// залежно від того, як їх скопіювала збірка. Шукаємо обидва варіанти,
    /// щоб екран ніколи не був порожнім (баг збірки 212).
    private var files: [URL] {
        let fm = FileManager.default
        if let dir = Bundle.main.url(forResource: "LICENSES", withExtension: nil),
           let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let texts = items.filter { $0.pathExtension.lowercased() == "txt" }
            if !texts.isEmpty { return texts.sorted { $0.lastPathComponent < $1.lastPathComponent } }
        }
        let names = ["GPL-3.0", "LGPL-2.1", "Apache-2.0-sonic", "BSL-1.0",
                     "MIT-ZIPFoundation", "BSD-3-Clause-hts_engine",
                     "CC-BY-ND-4.0", "CMU-Festvox", "CMU-cmudict"]
        return names.compactMap { Bundle.main.url(forResource: $0, withExtension: "txt") }
    }

    var body: some View {
        List {
            if files.isEmpty {
                Text("Тексти ліцензій не знайдено у цій збірці. Вони доступні у репозиторії проєкту, тека LICENSES.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(files, id: \.self) { file in
                    NavigationLink {
                        LicenseTextDetailView(file: file)
                    } label: {
                        Text(file.deletingPathExtension().lastPathComponent)
                    }
                    .accessibilityLabel("Ліцензія \(file.deletingPathExtension().lastPathComponent)")
                }
            }
        }
        .navigationTitle("Повні тексти")
    }
}

private struct LicenseTextDetailView: View {
    let file: URL

    var body: some View {
        ScrollView {
            Text((try? String(contentsOf: file, encoding: .utf8)) ?? "Не вдалося прочитати текст ліцензії.")
                .font(.footnote)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(file.deletingPathExtension().lastPathComponent)
    }
}

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

    /// Українська назва для екрана і VoiceOver: латинське ім'я рушій читає з
    /// англійським акцентом (аудит Даші, збірка 206, п.4). Двигун і система
    /// знають голос лише за profileName/identifier — їх не чіпаємо.
    var displayName: String {
        switch profileName {
        case "Anatol": return "Анатол"
        case "Marianna": return "Маріанна"
        case "Natalia": return "Наталія"
        case "Volodymyr": return "Володимир"
        default: return name
        }
    }

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
    var sentencePauseStrength: RHVoicePauseStrength = .none
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
    @Published var sentencePauseStrength: RHVoicePauseStrength
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
    @Published var abbreviationsAsWordsEnabled: Bool = true
    @Published var abbreviationDictionaryEnabled: Bool = true
    @Published var phoneNumberProcessingEnabled: Bool = true
    @Published var phoneNumberReadingMode: RHVoicePhoneNumberReadingMode = .groups
    @Published var personalDictionaryEntries: [PersonalDictionaryEntry]
    @Published var personalDictionaryStatus: PersonalDictionaryFileStatus
    @Published var abbreviationDictionaryEntries: [AbbreviationDictionaryEntry] = []
    @Published var abbreviationDictionaryShareURL: URL?
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
        self.sentencePauseStrength = general.sentencePauseStrength
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
                sentencePauseStrength: general.sentencePauseStrength,
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
                    fallbackSentencePauseStrength: sentencePauseStrength,
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
            let abbreviationEntries = (try? AbbreviationDictionary.loadEntries().get()) ?? []
            let status = PersonalUserDictionary.fileStatus()
            let logSize = DebugLogShareHelper.logSize()
            let shareURL = DebugLogShareHelper.logExists() ? DebugLogShareHelper.logURL : nil
            DispatchQueue.main.async {
                self?.applyLoadedState(snapshot: snapshot, entries: entries, abbreviationEntries: abbreviationEntries, status: status, logSize: logSize, shareURL: shareURL)
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
        abbreviationEntries: [AbbreviationDictionaryEntry],
        status: PersonalDictionaryFileStatus,
        logSize: Int,
        shareURL: URL?
    ) {
        let storedEnabled = Set(snapshot.enabledVoiceIdentifiers)
        let initialRate = snapshot.generalSettings.rate
        let initialVolume = Self.clampBaselineMultiplier(snapshot.generalSettings.volume)
        let initialSpeedMultiplier = Self.clampSpeedMultiplier(snapshot.generalSettings.speedMultiplier)
        let initialSentencePauseStrength = snapshot.generalSettings.sentencePauseStrength
        let initialWordGap = Self.clampWordGap(snapshot.generalSettings.wordGap)

        enabledVoiceIdentifiers = Self.normalizedEnabledVoices(storedEnabled)
        selectedVoiceIdentifier = snapshot.selectedVoiceIdentifier
        volume = initialVolume
        speedMultiplier = initialSpeedMultiplier
        sentencePauseStrength = initialSentencePauseStrength
        wordGap = initialWordGap
        pitch = snapshot.generalSettings.pitch
        personalDictionaryEntries = entries
        abbreviationDictionaryEntries = abbreviationEntries
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
                    sentencePauseStrength: stored.settings.sentencePauseStrength,
                    wordGap: Self.clampWordGap(stored.settings.wordGap),
                    pitch: 1.0
                ).neutralizedVoiceOverControlledSettings())
            }
            return (voice.identifier, ContentViewModel.loadStoredSettings(for: voice.identifier, fallbackRate: initialRate, fallbackVolume: initialVolume, fallbackSpeedMultiplier: initialSpeedMultiplier, fallbackSentencePauseStrength: initialSentencePauseStrength, fallbackWordGap: initialWordGap, fallbackPitch: snapshot.generalSettings.pitch))
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
                fallbackSentencePauseStrength: sentencePauseStrength,
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
        setStatus("Зробити голос \(voice.displayName) доступним: \(enabled ? "Увімкнено" : "Вимкнено").")
    }

    func selectVoiceForPreview(_ voice: VoiceDefinition) {
        if !isEnabled(voice) {
            enabledVoiceIdentifiers.insert(voice.identifier)
        }
        selectedVoiceIdentifier = voice.identifier
        persistVoiceState()
        setStatus("Голос \(voice.displayName) вибрано для прослуховування.")
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

    func reloadAbbreviationDictionary() {
        guard sharedStorageState == .ready else { return }
        Self.storageQueue.async { [weak self] in
            let entries = (try? AbbreviationDictionary.loadEntries().get()) ?? []
            DispatchQueue.main.async { self?.abbreviationDictionaryEntries = entries }
        }
    }

    func prepareAbbreviationDictionaryExport() {
        guard sharedStorageState == .ready else { return }
        Self.storageQueue.async { [weak self] in
            do {
                let entries = try AbbreviationDictionary.loadEntries().get()
                let url = try AbbreviationDictionary.makeExportFile(entries: entries)
                DispatchQueue.main.async { self?.abbreviationDictionaryShareURL = url }
            } catch {
                DispatchQueue.main.async { self?.setStatus("Не вдалося підготувати файл словника: \(error.localizedDescription)") }
            }
        }
    }

    func importAbbreviationDictionary(_ preview: AbbreviationDictionaryImportPreview, mode: AbbreviationDictionaryImportMode) {
        guard sharedStorageState == .ready else {
            setStatus(AbbreviationDictionaryError.appGroupUnavailable.localizedDescription)
            return
        }
        Self.storageQueue.async { [weak self] in
            do {
                let existing = try AbbreviationDictionary.loadEntries().get()
                let result = AbbreviationDictionary.applyImport(preview, to: existing, mode: mode)
                try AbbreviationDictionary.save(entries: result.entries)
                DispatchQueue.main.async {
                    self?.abbreviationDictionaryEntries = result.entries
                    self?.prepareAbbreviationDictionaryExport()
                    self?.setStatus(result.summary.spokenDescription)
                }
            } catch {
                DispatchQueue.main.async { self?.setStatus("Не вдалося завантажити словник: \(error.localizedDescription)") }
            }
        }
    }

    func reportAbbreviationDictionaryMessage(_ message: String) {
        setStatus(message)
    }

    func saveAbbreviationDictionaryEntry(oldAbbreviation: String?, abbreviation: String, replacement: String) -> Bool {
        guard sharedStorageState == .ready else {
            setStatus(AbbreviationDictionaryError.appGroupUnavailable.localizedDescription)
            return false
        }
        do {
            if let oldAbbreviation {
                try AbbreviationDictionary.updateEntry(oldAbbreviation: oldAbbreviation, abbreviation: abbreviation, replacement: replacement)
                setStatus("Запис словника замін оновлено.")
            } else {
                try AbbreviationDictionary.addEntry(abbreviation: abbreviation, replacement: replacement)
                setStatus("Запис додано до словника замін.")
            }
            reloadAbbreviationDictionary()
            prepareAbbreviationDictionaryExport()
            return true
        } catch {
            setStatus(error.localizedDescription)
            return false
        }
    }

    func removeAbbreviationDictionaryEntry(_ entry: AbbreviationDictionaryEntry) {
        guard sharedStorageState == .ready else {
            setStatus(AbbreviationDictionaryError.appGroupUnavailable.localizedDescription)
            return
        }
        do {
            try AbbreviationDictionary.removeEntry(abbreviation: entry.abbreviation)
            reloadAbbreviationDictionary()
            prepareAbbreviationDictionaryExport()
            setStatus("Запис «\(entry.abbreviation)» видалено зі словника замін.")
        } catch {
            setStatus(error.localizedDescription)
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
                self?.abbreviationsAsWordsEnabled = defaults?.object(forKey: RHVoiceSharedSettings.abbreviationsAsWordsKey) == nil
                    ? true : (defaults?.bool(forKey: RHVoiceSharedSettings.abbreviationsAsWordsKey) ?? true)
                self?.abbreviationDictionaryEnabled = defaults?.object(forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey) == nil
                    ? true : (defaults?.bool(forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey) ?? true)
                self?.phoneNumberProcessingEnabled = defaults?.object(forKey: RHVoiceSharedSettings.phoneNumberProcessingKey) == nil
                    ? true : (defaults?.bool(forKey: RHVoiceSharedSettings.phoneNumberProcessingKey) ?? true)
                self?.phoneNumberReadingMode = defaults?.string(forKey: RHVoiceSharedSettings.phoneNumberReadingModeKey)
                    .flatMap(RHVoicePhoneNumberReadingMode.init(rawValue:)) ?? .groups
            }
        }
    }

    func setDatesAsWords(_ enabled: Bool) {
        datesAsWordsEnabled = enabled
        announceToggleState("Читати дати словами", enabled: enabled)
        Self.storageQueue.async {
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?
                .set(enabled, forKey: RHVoiceSharedSettings.datesAsWordsKey)
        }
    }

    func setTimeAsWords(_ enabled: Bool) {
        timeAsWordsEnabled = enabled
        announceToggleState("Читати час словами", enabled: enabled)
        Self.storageQueue.async {
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?.set(enabled, forKey: RHVoiceSharedSettings.timeAsWordsKey)
        }
    }

    func setAbbreviationsAsWords(_ enabled: Bool) {
        abbreviationsAsWordsEnabled = enabled
        announceToggleState("Розгортати скорочення", enabled: enabled)
        Self.storageQueue.async {
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?.set(enabled, forKey: RHVoiceSharedSettings.abbreviationsAsWordsKey)
        }
    }

    func setAbbreviationDictionaryEnabled(_ enabled: Bool) {
        abbreviationDictionaryEnabled = enabled
        announceToggleState("Застосовувати словник замін", enabled: enabled)
        Self.storageQueue.async {
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?.set(enabled, forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey)
        }
    }

    func setPhoneNumberProcessing(_ enabled: Bool) {
        phoneNumberProcessingEnabled = enabled
        announceToggleState("Обробляти телефонні номери", enabled: enabled)
        Self.storageQueue.async {
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?.set(enabled, forKey: RHVoiceSharedSettings.phoneNumberProcessingKey)
        }
    }

    func setPhoneNumberReadingMode(_ mode: RHVoicePhoneNumberReadingMode) {
        phoneNumberReadingMode = mode
        Self.storageQueue.async { [weak self] in
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?.set(mode.rawValue, forKey: RHVoiceSharedSettings.phoneNumberReadingModeKey)
            DispatchQueue.main.async {
                self?.setStatus(mode == .groups ? "Номери читаються групами." : "Номери читаються по цифрах.")
            }
        }
    }

    func setExtendedDiagnostics(_ enabled: Bool) {
        extendedDiagnosticsEnabled = enabled
        announceToggleState("Розширена діагностика", enabled: enabled)
        Self.storageQueue.async {
            UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)?
                .set(enabled, forKey: RHVoiceSharedSettings.extendedDiagnosticsKey)
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

    func updateGeneralSentencePauseStrength(_ value: RHVoicePauseStrength) {
        sentencePauseStrength = value
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
        defaults.set(normalizedSettings.sentencePauseStrength.rawValue, forKey: "\(prefix).sentencePauseStrength")
        // Rollback safety only, written immediately for the same reason as in
        // `persistGeneralSettings()` (task-226 round 4, п.6): `persistSharedSnapshot()`
        // below may not run this session if `sharedStorageState` never reaches `.ready`.
        defaults.set(normalizedSettings.sentencePauseStrength.legacyMilliseconds, forKey: "\(prefix).sentencePause")
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
        setStatus("Готую голос \(voice.displayName)…")
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
        defaults.set(sentencePauseStrength.rawValue, forKey: RHVoiceSharedSettings.sentencePauseStrengthKey)
        // Rollback safety only (see `RHVoicePauseStrength.legacyMilliseconds`),
        // written immediately: `persistSharedSnapshot()` below writes the same
        // legacy key too, but only after a background disk round-trip guarded
        // by `sharedStorageState == .ready`, which can simply never run. Without
        // this line a user who rolls back to build ≤225 while that guard is
        // blocking would read a stale legacy value (task-226 round 4, п.6).
        defaults.set(sentencePauseStrength.legacyMilliseconds, forKey: RHVoiceSharedSettings.sentencePauseKey)
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

    /// Toggle values must be spoken while VoiceOver still has focus on that
    /// toggle. Persisting to the App Group happens independently and must not
    /// delay this user feedback.
    private func announceToggleState(_ title: String, enabled: Bool) {
        let message = "\(title): \(enabled ? "Увімкнено" : "Вимкнено")."
        statusMessage = message
        LogCollector.shared.log(message)
        DispatchQueue.main.async { announce(message) }
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
            sentencePauseStrength: sentencePauseStrength,
            wordGap: Self.clampWordGap(wordGap),
            pitch: 1.0
        )
        let perVoice = Dictionary(uniqueKeysWithValues: voiceCatalog.map { voice -> (String, RHVoicePerVoiceSettings) in
            let state = voiceSettingsByIdentifier[voice.identifier] ?? VoiceSettingsState(
                useCustomSettings: true,
                rate: 0.5,
                volume: 1.0,
                speedMultiplier: settings.speedMultiplier,
                sentencePauseStrength: settings.sentencePauseStrength,
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
                        sentencePauseStrength: state.sentencePauseStrength,
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
        fallbackSentencePauseStrength: RHVoicePauseStrength,
        fallbackWordGap: Double,
        fallbackPitch: Double
    ) -> VoiceSettingsState {
        let prefix = voiceSettingsKeyPrefix(for: identifier)
        return VoiceSettingsState(
            useCustomSettings: true,
            rate: 0.5,
            volume: 1.0,
            speedMultiplier: Self.clampSpeedMultiplier(defaults.object(forKey: "\(prefix).speedMultiplier") as? Double ?? fallbackSpeedMultiplier),
            sentencePauseStrength: RHVoicePauseStrength.resolved(
                from: defaults,
                key: "\(prefix).sentencePauseStrength",
                legacyMillisecondsKey: "\(prefix).sentencePause",
                fallback: fallbackSentencePauseStrength
            ),
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
                        .accessibilityLabel("\(voice.displayName), \(voice.languageTitle)")
                        .accessibilityValue(model.isEnabled(voice) ? "Доступний" : "Вимкнений")
                        .accessibilityHint("Відкрити налаштування голосу")
                    }
                }

                Section {
                    personalDictionaryLink
                    abbreviationDictionaryLink
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

                // Роздiл дiагностики лишається ТIЛЬКИ у замiрочних збiрках.
                // Причина: забрати журнал користувач не може нi за яких налаштувань —
                // розширенню заборонена будь-яка запис (доведено 26.08.2026), а системний
                // журнал знiмається лише комп'ютером по кабелю. Перемикач, який нiчого не
                // дає людинi, — смiття в iнтерфейсi i зайве питання на перевiрцi Apple.
                #if RHVOICE_DIAG
                diagnosticSection
                #endif
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
                        .accessibilityLabel("\(voice.displayName), \(voice.languageTitle)")
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

                abbreviationDictionaryLink
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

                // Роздiл дiагностики лишається ТIЛЬКИ у замiрочних збiрках.
                // Причина: забрати журнал користувач не може нi за яких налаштувань —
                // розширенню заборонена будь-яка запис (доведено 26.08.2026), а системний
                // журнал знiмається лише комп'ютером по кабелю. Перемикач, який нiчого не
                // дає людинi, — смiття в iнтерфейсi i зайве питання на перевiрцi Apple.
                #if RHVOICE_DIAG
                diagnosticSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                #endif
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
            Text(voice.displayName)
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
            .accessibilityValue(model.datesAsWordsEnabled ? "Увімкнено" : "Вимкнено")
            .accessibilityHint("Увімкнено: повні дати, як-от 10.07.2026, читаються словами — «десяте липня дві тисячі двадцять шостого року». Вимкнено: дати читаються цифрами.")

            Text("Стосується повних дат із чотиризначним роком. Короткі дати (10.07.26) завжди читаються цифрами.")
                .font(.footnote)
                .foregroundColor(.secondary)

            Toggle(isOn: Binding(get: { model.timeAsWordsEnabled }, set: { model.setTimeAsWords($0) })) {
                Label("Читати час словами", systemImage: "clock")
            }
            .accessibilityValue(model.timeAsWordsEnabled ? "Увімкнено" : "Вимкнено")
            .accessibilityHint("Увімкнено: 17:01 читається як час словами. Вимкнено: RHVoice не розгортає запис часу у години та хвилини.")

            Toggle(isOn: Binding(get: { model.abbreviationsAsWordsEnabled }, set: { model.setAbbreviationsAsWords($0) })) {
                Label("Розгортати скорочення", systemImage: "textformat.abc")
            }
            .accessibilityValue(model.abbreviationsAsWordsEnabled ? "Увімкнено" : "Вимкнено")
            .accessibilityHint("Увімкнено: 5 хв, 2 год і 30 сек читаються повними словами. Вимкнено: скорочення лишаються без розгортання.")

            Toggle(isOn: Binding(get: { model.phoneNumberProcessingEnabled }, set: { model.setPhoneNumberProcessing($0) })) {
                Label("Обробляти телефонні номери", systemImage: "phone")
            }
            .accessibilityValue(model.phoneNumberProcessingEnabled ? "Увімкнено" : "Вимкнено")
            .accessibilityHint("Увімкнено: RHVoice розпізнає номери та читає їх обраним способом. Вимкнено: номер читає система без обробки RHVoice.")

            Picker("Читати номер", selection: Binding(get: { model.phoneNumberReadingMode }, set: { model.setPhoneNumberReadingMode($0) })) {
                Text("групами").tag(RHVoicePhoneNumberReadingMode.groups)
                Text("по цифрах").tag(RHVoicePhoneNumberReadingMode.digits)
            }
            .pickerStyle(.segmented)
            .disabled(!model.phoneNumberProcessingEnabled)
            .accessibilityHint("Групами: кожна частина номера читається як число. По цифрах: стара поведінка для запису номера на слух.")

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
            .accessibilityValue(model.extendedDiagnosticsEnabled ? "Увімкнено" : "Вимкнено")
            .accessibilityHint("Коли увімкнено, застосунок записує діагностику у файл. Діагностика синтезатора на iPhone доступна через кабель у системному журналі: iOS не дозволяє speech-extension записувати спільний файл.")

            Text("Цей файл містить діагностику застосунку. На iPhone журнал синтезатора VoiceOver доступний лише по кабелю в системному журналі: iOS забороняє extension записувати його у спільний файл.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .accessibilityLabel("Підказка щодо діагностики")

            NavigationLink {
                CapturedRequestsView()
            } label: {
                Label("Що почув синтезатор", systemImage: "text.magnifyingglass")
            }
            .accessibilityLabel("Що почув синтезатор")
            .accessibilityHint("Показує текст, який система віддала голосу. Потрібно для розбору скарг на читання чисел, часу і номерів.")

            Button {
                model.clearDebugLog()
            } label: {
                Label("Очистити лог", systemImage: "trash")
            }
            .accessibilityLabel("Очистити лог")
                .accessibilityHint("Стирає журнал застосунку. Не впливає на журнал синтезатора VoiceOver.")

            // Кеш із моделі, а не прямий виклик до контейнера: тіло view виконується
            // на main під час обходу VoiceOver, а containerURL/stat на macOS 26
            // може заблокуватись (task-082).
            if let url = model.debugLogShareURL {
                ShareLink(item: url) {
                    Label("Поділитись журналом застосунку", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Поділитись журналом застосунку")
                .accessibilityHint("Відкриває системне меню для надсилання діагностики застосунку. Журнал VoiceOver доступний по кабелю.")
            } else {
                Text("Журнал застосунку ще порожній.")
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

    private var abbreviationDictionaryLink: some View {
        NavigationLink {
            AbbreviationDictionaryView(
                entries: model.abbreviationDictionaryEntries,
                enabled: Binding(get: { model.abbreviationDictionaryEnabled }, set: { model.setAbbreviationDictionaryEnabled($0) }),
                reload: { model.reloadAbbreviationDictionary() },
                prepareExport: { model.prepareAbbreviationDictionaryExport() },
                shareURL: model.abbreviationDictionaryShareURL,
                save: { old, abbreviation, replacement in
                    model.saveAbbreviationDictionaryEntry(oldAbbreviation: old, abbreviation: abbreviation, replacement: replacement)
                },
                delete: { model.removeAbbreviationDictionaryEntry($0) },
                importDictionary: { preview, mode in model.importAbbreviationDictionary(preview, mode: mode) },
                reportMessage: { model.reportAbbreviationDictionaryMessage($0) }
            )
        } label: {
            Label("Словник замін", systemImage: "text.book.closed")
        }
        .accessibilityLabel("Словник замін")
        .accessibilityHint("Тут можна задати, як читати будь-яке слово: скорочення, абревіатуру, ім'я чи назву.")
    }

    private var downloadableLanguagesLink: some View {
        NavigationLink {
            DownloadableLanguagesView(downloadManager: voiceDownloadManager)
        } label: {
            Label("Мови", systemImage: "globe")
        }
        .accessibilityLabel("Мови")
        .accessibilityHint("Показує мови, голоси яких є у застосунку.")
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
                Button {
                    showsTechnicalInfo.toggle()
                    announce("Технічна інформація: \(showsTechnicalInfo ? "Розгорнуто" : "Згорнуто").")
                } label: {
                    HStack {
                        Text("Технічна інформація")
                        Spacer()
                        Image(systemName: showsTechnicalInfo ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
                .accessibilityLabel("Технічна інформація")
                .accessibilityValue(showsTechnicalInfo ? "Розгорнуто" : "Згорнуто")
                .accessibilityHint("Подвійний дотик розгортає або згортає стан файлів особистого словника.")

                if showsTechnicalInfo {
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
                            .accessibilityHint("Відкрити редагування запису. Доступна дія: Видалити.")
                            .accessibilityAction(named: "Видалити") {
                                entryPendingDeletion = entry
                            }

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

private struct AbbreviationDictionaryView: View {
    let entries: [AbbreviationDictionaryEntry]
    @Binding var enabled: Bool
    let reload: () -> Void
    let prepareExport: () -> Void
    let shareURL: URL?
    let save: (String?, String, String) -> Bool
    let delete: (AbbreviationDictionaryEntry) -> Void
    let importDictionary: (AbbreviationDictionaryImportPreview, AbbreviationDictionaryImportMode) -> Void
    let reportMessage: (String) -> Void

    @State private var editingEntry: AbbreviationDictionaryEntry?
    @State private var isAddingEntry = false
    @State private var pendingDeletion: AbbreviationDictionaryEntry?
    @State private var isImporting = false
    @State private var pendingImport: AbbreviationDictionaryImportPreview?

    var body: some View {
        List {
            Section {
                Toggle("Застосовувати словник замін", isOn: $enabled)
                    .accessibilityLabel("Застосовувати словник замін")
                    .accessibilityValue(enabled ? "Увімкнено" : "Вимкнено")
                    .accessibilityHint("Увімкнено: базові та власні заміни застосовуються під час читання. Вимкнено: словник не змінює текст.")
            }

            Section("Власні записи") {
                Text("Тут можна задати, як читати будь-яке слово: скорочення, абревіатуру, ім'я чи назву.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button { isAddingEntry = true } label: {
                    Label("Додати", systemImage: "plus")
                }
                .accessibilityLabel("Додати запис до словника замін")
                .accessibilityHint("Відкрити форму нового слова або заміни.")

                if entries.isEmpty {
                    Text("Власних записів ще немає.")
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Власний словник замін порожній")
                } else {
                    ForEach(entries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.abbreviation).font(.headline)
                                Text(entry.replacement).foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(entry.abbreviation), читати як \(entry.replacement)")
                        .accessibilityHint("Відкрити редагування запису. Доступна дія: Видалити.")
                        .accessibilityAction(named: "Видалити") {
                            pendingDeletion = entry
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingDeletion = entry } label: {
                                Label("Видалити", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in pendingDeletion = offsets.map { entries[$0] }.first }
                }
            }

            Section("Базові заміни") {
                Text("Торкніться правила, щоб створити власне перевизначення. Власний запис із таким самим словом має пріоритет.")
                    .font(.footnote).foregroundColor(.secondary)
                ForEach(AbbreviationDictionary.bundledEntries) { entry in
                    Button { editingEntry = entry } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.abbreviation).font(.headline)
                            Text("читати як \(entry.replacement)").foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Базова заміна: \(entry.abbreviation), читати як \(entry.replacement)")
                    .accessibilityHint("Створити власне перевизначення цього правила")
                }
            }

            Section("Обмін") {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Поділитися словником", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Поділитися словником")
                    .accessibilityHint("Відкриває системне меню, щоб надіслати файл власних скорочень.")
                } else {
                    ProgressView("Підготовка файлу словника")
                        .accessibilityLabel("Підготовка файлу словника")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("Завантажити словник із файлу", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Завантажити словник із файлу")
                .accessibilityHint("Відкрити системний вибір текстового файлу словника.")
            }

        }
        .navigationTitle("Словник замін")
        .sheet(isPresented: $isAddingEntry) {
            AbbreviationDictionaryEditorView(entry: nil, save: save)
        }
        .sheet(item: $editingEntry) { entry in
            AbbreviationDictionaryEditorView(entry: entry, save: save)
        }
        .onAppear {
            reload()
            prepareExport()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case let .failure(error) = result { reportMessage("Не вдалося відкрити файл словника: \(error.localizedDescription)") }
                return
            }
            readImportFile(url)
        }
        .confirmationDialog(
            pendingDeletion.map { "Видалити запис «\($0.abbreviation)»?" } ?? "Видалити запис?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            if let entry = pendingDeletion {
                Button("Видалити", role: .destructive) { delete(entry); pendingDeletion = nil }
            }
            Button("Скасувати", role: .cancel) { pendingDeletion = nil }
        }
        .confirmationDialog(
            "Як завантажити словник?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible
        ) {
            Button("Додати до наявних") {
                if let preview = pendingImport { importDictionary(preview, .add) }
                pendingImport = nil
            }
            Button("Замінити мої записи", role: .destructive) {
                if let preview = pendingImport { importDictionary(preview, .replace) }
                pendingImport = nil
            }
            Button("Скасувати", role: .cancel) { pendingImport = nil }
        } message: {
            if let preview = pendingImport {
                Text("Знайдено записів: \(preview.entries.count). Некоректних рядків буде пропущено: \(preview.skippedLines).")
            }
        }
    }

    private func readImportFile(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result: Result<AbbreviationDictionaryImportPreview, AbbreviationDictionaryError>
            do {
                result = AbbreviationDictionary.importPreview(from: try Data(contentsOf: url))
            } catch {
                result = .failure(.unreadableFile)
            }
            DispatchQueue.main.async {
                switch result {
                case let .success(preview): self.pendingImport = preview
                case let .failure(error): self.reportMessage(error.localizedDescription)
                }
            }
        }
    }
}

private struct AbbreviationDictionaryEditorView: View {
    let entry: AbbreviationDictionaryEntry?
    let save: (String?, String, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var abbreviation: String
    @State private var replacement: String
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var accessibilityFocusedField: Field?

    private enum Field {
        case abbreviation
        case replacement
    }

    init(entry: AbbreviationDictionaryEntry?, save: @escaping (String?, String, String) -> Bool) {
        self.entry = entry
        self.save = save
        _abbreviation = State(initialValue: entry?.abbreviation ?? "")
        _replacement = State(initialValue: entry?.replacement ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Слово або скорочення") {
                    TextField("наприклад: БПЛА", text: $abbreviation)
                        .focused($focusedField, equals: .abbreviation)
                        .accessibilityFocused($accessibilityFocusedField, equals: .abbreviation)
                        .accessibilityLabel("Слово або скорочення")
                        .accessibilityHint("Точний запис, який треба замінити.")
                }
                Section("Як читати") {
                    TextField("наприклад: безпілотний літальний апарат", text: $replacement)
                        .focused($focusedField, equals: .replacement)
                        .accessibilityFocused($accessibilityFocusedField, equals: .replacement)
                        .accessibilityLabel("Як читати")
                        .accessibilityHint("Слова, якими треба замінити скорочення.")
                }
                Section("Дії") {
                    Button("Зберегти") {
                        if save(entry?.abbreviation, abbreviation, replacement) { dismiss() }
                    }
                    .accessibilityHint("Зберегти запис і застосувати його без перезапуску VoiceOver.")

                    Button("Скасувати") { dismiss() }
                }
            }
            .navigationTitle(entry == nil ? "Новий запис" : "Редагувати запис")
        }
        .onAppear {
            focusedField = .abbreviation
            DispatchQueue.main.async { accessibilityFocusedField = .abbreviation }
        }
    }
}

private struct AboutAcknowledgementView: View {
    var body: some View {
        List {
            Section("Застосунок") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RHVoice UA")
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

            Section("Повні тексти ліцензій") {
                NavigationLink {
                    LicenseTextsView()
                } label: {
                    Label("Відкрити повні тексти", systemImage: "doc.text")
                }
                .accessibilityLabel("Відкрити повні тексти ліцензій")
                .accessibilityHint("Тексти всіх ліцензій, що постачаються разом із застосунком.")
            }

            Section("Правова інформація") {
                Text(legalNoticeText)
                    .textSelection(.enabled)
                    .accessibilityLabel(legalNoticeText)
                Link("Вихідний код застосунку", destination: sourceCodeURL)
                    .accessibilityLabel("Вихідний код застосунку на GitHub")
                    .accessibilityHint("Відкриває репозиторій із повним вихідним кодом.")
                Text(buildIdentityText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel(buildIdentityText)
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
    @AccessibilityFocusState private var accessibilityFocusedField: Field?

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
                        .accessibilityFocused($accessibilityFocusedField, equals: .displayWord)
                        .personalDictionaryTextInputSettings()
                        .accessibilityLabel("Слово як воно пишеться")
                        .accessibilityHint("Слово як пишеться.")
                    TextField("", text: $stressedWord, prompt: Text("наприклад: листоп+ад"))
                        .focused($focusedField, equals: .stressedWord)
                        .accessibilityFocused($accessibilityFocusedField, equals: .stressedWord)
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
                        isPreviewPlaying ? stopPreview() : preview(stressedWord)
                    }
                    .disabled(stressedWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityAddTraits(.startsMediaSession)
                    .accessibilityLabel(isPreviewPlaying ? "Зупинити прослуховування" : "Перевірити слово")
                    .accessibilityHint("Промовляє введену вимову. Після збереження так само має звучати слово за словником.")
                }

                Section("Дії") {
                    Button("Зберегти") {
                        saveAndDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Зберегти запис")

                    Button("Скасувати") {
                        dismiss()
                    }
#if os(macOS)
                    .keyboardShortcut(.cancelAction)
#endif
                    .accessibilityLabel("Скасувати")
                }
            }
            .navigationTitle(entry == nil ? "Нове слово" : "Редагування")
        }
        .onAppear {
            focusedField = .displayWord
            DispatchQueue.main.async { accessibilityFocusedField = .displayWord }
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
                    .accessibilityLabel("Зробити голос \(voice.displayName) доступним")
                    .accessibilityValue(isEnabled ? "Увімкнено" : "Вимкнено")
                    .accessibilityHint("Керує доступністю цього голосу для VoiceOver.")
            }

            Section("Налаштування голосу") {
                Picker("Прискорювач", selection: acceleratorPresetBinding) {
                    ForEach(acceleratorPresets) { preset in
                        Text(preset.title).tag(preset.multiplier)
                    }
                }
                .accessibilityHint("Вибирає готовий множник темпу для голосу \(voice.displayName). Нормально не змінює системну швидкість VoiceOver.")

                sliderRow(
                    title: "Детальний множник",
                    value: settingBinding(\.speedMultiplier),
                    range: 0.8...1.6,
                    step: 0.05,
                    valueText: multiplierText(settings.speedMultiplier),
                    hint: "Точно налаштовує множник темпу для голосу \(voice.displayName). 1.0x не змінює системну швидкість VoiceOver."
                )

                Picker("Пауза після розділових знаків", selection: sentencePauseStrengthBinding) {
                    ForEach(RHVoicePauseStrength.allCases, id: \.self) { strength in
                        Text(strength.displayName).tag(strength)
                    }
                }
                .accessibilityHint("Встановлює паузу після крапки, коми, знаку оклику та знаку питання для голосу \(voice.displayName).")

                sliderRow(
                    title: "Проміжок між словами",
                    value: settingBinding(\.wordGap),
                    range: 0...300,
                    step: 10,
                    valueText: "\(Int(settings.wordGap)) мс",
                    hint: "Додає проміжок між словами для голосу \(voice.displayName)."
                )
            }

            Section {
                Button(isPreviewPlaying ? "Зупинити" : "Прослухати") {
                    isPreviewPlaying ? stopPreview() : playSample()
                }
                .accessibilityAddTraits(.startsMediaSession)
                .accessibilityLabel(isPreviewPlaying ? "Зупинити прослуховування" : "Прослухати голос \(voice.displayName)")
                .accessibilityHint("Промовляє стандартну тестову фразу цим голосом.")
            }
        }
        .navigationTitle(voice.displayName)
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

    private var sentencePauseStrengthBinding: Binding<RHVoicePauseStrength> {
        Binding(
            get: { settings.sentencePauseStrength },
            set: { newValue in
                settings.useCustomSettings = true
                settings.sentencePauseStrength = newValue
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
    // SwiftUI applies a Toggle/Navigation update after its action.  Posting in
    // that same run-loop turn is regularly swallowed by VoiceOver, especially
    // in a List.  Let the focused control publish its new value first, then
    // speak the result while that focus is still meaningful.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
#endif
}

#Preview {
    ContentView()
}
