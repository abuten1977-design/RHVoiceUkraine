import SwiftUI
import AVFAudio

private struct VoiceSelfCheckReport {
    let stored: String
    let published: String
    let abbreviationDictionary: String

    static let initial = Self(
        stored: NSLocalizedString("На пристрої збережено: перевірка ще не виконувалась.", comment: ""),
        published: NSLocalizedString("Опублікований список: перевірка ще не виконувалась.", comment: ""),
        abbreviationDictionary: NSLocalizedString("Словник замін: перевірка ще не виконувалась.", comment: "")
    )

    static func collect() -> Self {
        let voices = RHVoiceDownloadableVoices.scanInstalledVoices()
        let storedNames = voices.map { descriptor -> String in
            let id = descriptor.identifier.components(separatedBy: ".").last ?? descriptor.identifier
            let size = directorySize(RHVoiceDownloadableVoices.voiceDirectoryURL(id: id))
            return String(format: NSLocalizedString("%@ — %@ МБ", comment: ""), NSLocalizedString(descriptor.name, comment: ""), String(format: "%.1f", Double(size) / 1_048_576.0))
        }
        let stored = storedNames.isEmpty
            ? NSLocalizedString("На пристрої збережено: завантажених голосів немає.", comment: "")
            : String(format: NSLocalizedString("На пристрої збережено: %@.", comment: ""), storedNames.joined(separator: ", "))

        guard let catalog = RHVoicePublishedVoiceCatalog.loadPublished() else {
            return Self(
                stored: stored,
                published: NSLocalizedString("Опублікований список голосів відсутній.", comment: ""),
                abbreviationDictionary: abbreviationDictionaryStatus()
            )
        }
        let published = String(format: NSLocalizedString("Опубліковано голосів: %@, версія списку %@.", comment: ""), String(catalog.descriptors.count), String(catalog.revision))
        return Self(stored: stored, published: published, abbreviationDictionary: abbreviationDictionaryStatus())
    }

    private static func abbreviationDictionaryStatus() -> String {
        let defaults = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)
        let enabled = defaults?.object(forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey) == nil
            ? true : (defaults?.bool(forKey: RHVoiceSharedSettings.abbreviationDictionaryEnabledKey) ?? true)
        guard enabled else { return NSLocalizedString("Словник замін: вимкнено.", comment: "") }
        let user = (try? AbbreviationDictionary.loadEntries().get())?.count ?? 0
        return String(format: NSLocalizedString("Словник замін у застосунку: базових %@, власних %@.", comment: ""), String(AbbreviationDictionary.bundledEntries.count), String(user))
    }

    private static func directorySize(_ url: URL?) -> Int64 {
        guard let url,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return enumerator.reduce(into: Int64(0)) { total, item in
            guard let item = item as? URL else { return }
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

/// Завантажувані мови приховані в ПЕРШОМУ релізі App Store.
/// Причина: щойно завантажений голос мовчить, поки процес розширення не
/// перезапуститься (розбір 31.08.2026, LATEST_HANDOFF). Код лишається на місці —
/// щоб повернути, достатньо змінити прапорець на `true`.
private let showDownloadableLanguages = false

/// Екран «Мови»: вбудована українська + додаткові мови, голоси яких
/// завантажуються за потреби (v1 — англійська).
struct DownloadableLanguagesView: View {
    @ObservedObject var downloadManager: VoiceDownloadManager
    @State private var selfCheckReport = VoiceSelfCheckReport.initial
    @State private var isRefreshingSelfCheck = false

    var body: some View {
        List {
            Section("Вбудована мова") {
                HStack {
                    Text("Українська")
                    Spacer()
                    Text("4 голоси")
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Українська, 4 голоси, вбудована мова, завжди доступна")
            }

            if showDownloadableLanguages {
            Section("Додаткові мови") {
                switch downloadManager.manifestState {
                case .idle, .loading:
                    HStack {
                        ProgressView()
                        Text("Завантаження списку мов…")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Завантаження списку мов")
                case .failed(let message):
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("Спробувати ще раз") {
                        Task { await downloadManager.loadManifest(forceNetwork: true) }
                    }
                case .loaded:
                    if let manifest = downloadManager.manifest {
                        ForEach(manifest.languages) { language in
                            NavigationLink {
                                DownloadableLanguageVoicesView(
                                    language: language,
                                    downloadManager: downloadManager
                                )
                            } label: {
                                HStack {
                                    Text(NSLocalizedString(language.nameUk, comment: ""))
                                    Spacer()
                                    Text(installedCountText(language))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityLabel("\(NSLocalizedString(language.nameUk, comment: "")), \(installedCountText(language))")
                            .accessibilityHint("Відкрити список голосів для завантаження")
                        }
                    }
                }
            }
            }

            if !downloadManager.statusMessage.isEmpty {
                Section {
                    Text(downloadManager.statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel(String(format: NSLocalizedString("Стан: %@", comment: ""), downloadManager.statusMessage))
                }
            }

            selfCheckSection
        }
        .navigationTitle("Мови")
        .onAppear {
            if showDownloadableLanguages {
                downloadManager.refresh()
            } else {
                downloadManager.refreshInstalled()
            }
            refreshSelfCheck()
        }
    }

    private var selfCheckSection: some View {
        Section("Самоперевірка") {
            if showDownloadableLanguages {
                Text(selfCheckReport.stored)
                    .accessibilityLabel(selfCheckReport.stored)
            }
            Text(selfCheckReport.published)
                .accessibilityLabel(selfCheckReport.published)
            Text(selfCheckReport.abbreviationDictionary)
                .accessibilityLabel(selfCheckReport.abbreviationDictionary)
            Button("Оновити самоперевірку") { refreshSelfCheck() }
                .disabled(isRefreshingSelfCheck)
                .accessibilityLabel("Оновити самоперевірку")
                .accessibilityHint("Перевірити список голосів і словник замін.")
            Button("Полагодити голоси") {
                downloadManager.repairVoices()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { refreshSelfCheck() }
            }
            .accessibilityLabel("Полагодити голоси")
            .accessibilityHint("Переопублікувати список голосів і попросити систему оновити його без перезавантаження iPhone.")
        }
    }

    private func refreshSelfCheck() {
        isRefreshingSelfCheck = true
        Task.detached(priority: .utility) {
            let report = VoiceSelfCheckReport.collect()
            await MainActor.run {
                selfCheckReport = report
                isRefreshingSelfCheck = false
            }
        }
    }

    private func installedCountText(_ language: ManifestLanguage) -> String {
        let installed = language.voices.filter { downloadManager.isInstalled($0) }.count
        if installed == 0 {
            return NSLocalizedString("не завантажено", comment: "")
        }
        return String(format: NSLocalizedString("завантажено: %@ із %@", comment: ""), String(installed), String(language.voices.count))
    }
}

/// Список голосів однієї додаткової мови: завантажити / видалити / прогрес.
struct DownloadableLanguageVoicesView: View {
    let language: ManifestLanguage
    @ObservedObject var downloadManager: VoiceDownloadManager
    @State private var voicePendingDelete: ManifestVoice?

    var body: some View {
        List {
            Section {
                Text("Завантажений голос одразу з'являється на головному екрані поруч з українськими (там його можна вмикати, вимикати і слухати зразок) та у списку голосів VoiceOver.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("Голоси") {
                ForEach(language.voices) { voice in
                    voiceRow(voice)
                }
            }

            if !downloadManager.statusMessage.isEmpty {
                Section {
                    Text(downloadManager.statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel(String(format: NSLocalizedString("Стан: %@", comment: ""), downloadManager.statusMessage))
                }
            }
        }
        .navigationTitle(NSLocalizedString(language.nameUk, comment: ""))
        .onAppear { downloadManager.refreshInstalled() }
        .alert(item: $voicePendingDelete) { voice in
            Alert(
                title: Text(String(format: NSLocalizedString("Видалити голос %@?", comment: ""), NSLocalizedString(voice.userFacingName, comment: ""))),
                message: Text("Голос зникне з VoiceOver. Його можна буде завантажити знову."),
                primaryButton: .destructive(Text("Видалити")) {
                    downloadManager.delete(voice)
                },
                secondaryButton: .cancel(Text("Скасувати"))
            )
        }
    }

    // Кнопка — ОКРЕМИЙ accessibility-елемент (не .combine на весь рядок):
    // комбінований рядок із кнопкою всередині у SwiftUI може не активувати дію
    // подвійним тапом VoiceOver (ризик із чек-листа доступності build 191).
    @ViewBuilder
    private func voiceRow(_ voice: ManifestVoice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(voice.userFacingName, comment: ""))
                Text("\(NSLocalizedString(voice.genderUk, comment: "")), \(voice.sizeMegabytesText)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel(voice))
            .accessibilityHint(downloadManager.isInstalled(voice)
                ? NSLocalizedString("Доступна дія: Видалити голос.", comment: "")
                : NSLocalizedString("Доступна дія: Завантажити голос.", comment: ""))
            .accessibilityAction(named: downloadManager.isInstalled(voice) ? NSLocalizedString("Видалити голос", comment: "") : NSLocalizedString("Завантажити голос", comment: "")) {
                if downloadManager.isInstalled(voice) {
                    voicePendingDelete = voice
                } else {
                    downloadManager.download(voice, language: language)
                }
            }

            Spacer()

            if let progress = downloadManager.downloadProgress[voice.id] {
                ProgressView(value: progress)
                    .frame(width: 80)
                    .accessibilityLabel(String(format: NSLocalizedString("Завантаження %@", comment: ""), NSLocalizedString(voice.userFacingName, comment: "")))
                    .accessibilityValue(String(format: NSLocalizedString("%@ відсотків", comment: ""), String(Int(progress * 100))))
            } else if downloadManager.isInstalled(voice) {
                Button("Видалити") {
                    voicePendingDelete = voice
                }
                .foregroundColor(.red)
                .accessibilityLabel(String(format: NSLocalizedString("Видалити голос %@", comment: ""), NSLocalizedString(voice.userFacingName, comment: "")))
                .accessibilityHint("Голос зникне з VoiceOver, його можна буде завантажити знову.")
            } else {
                Button("Завантажити") {
                    downloadManager.download(voice, language: language)
                }
                .accessibilityLabel(String(format: NSLocalizedString("Завантажити голос %@, %@", comment: ""), NSLocalizedString(voice.userFacingName, comment: ""), voice.sizeMegabytesText))
                .accessibilityHint("Після завантаження голос з'явиться у списку голосів і у VoiceOver.")
            }
        }
    }

    private func rowAccessibilityLabel(_ voice: ManifestVoice) -> String {
        var label = "\(NSLocalizedString(voice.userFacingName, comment: "")), \(NSLocalizedString(voice.genderUk, comment: "")), \(voice.sizeMegabytesText)"
        if let progress = downloadManager.downloadProgress[voice.id] {
            label += String(format: NSLocalizedString(", завантаження %@ відсотків", comment: ""), String(Int(progress * 100)))
        } else if downloadManager.isInstalled(voice) {
            label += NSLocalizedString(", завантажено", comment: "")
        } else {
            label += NSLocalizedString(", не завантажено", comment: "")
        }
        return label
    }
}
