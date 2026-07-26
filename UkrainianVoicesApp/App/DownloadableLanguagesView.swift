import SwiftUI

/// Екран «Мови»: вбудована українська + додаткові мови, голоси яких
/// завантажуються за потреби (v1 — англійська).
struct DownloadableLanguagesView: View {
    @ObservedObject var downloadManager: VoiceDownloadManager

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
                                    Text(language.nameUk)
                                    Spacer()
                                    Text(installedCountText(language))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .accessibilityLabel("\(language.nameUk), \(installedCountText(language))")
                            .accessibilityHint("Відкрити список голосів для завантаження")
                        }
                    }
                }
            }

            if !downloadManager.statusMessage.isEmpty {
                Section {
                    Text(downloadManager.statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Стан: \(downloadManager.statusMessage)")
                }
            }
        }
        .navigationTitle("Мови")
        .onAppear { downloadManager.refresh() }
    }

    private func installedCountText(_ language: ManifestLanguage) -> String {
        let installed = language.voices.filter { downloadManager.isInstalled($0) }.count
        if installed == 0 {
            return "не завантажено"
        }
        return "завантажено: \(installed) із \(language.voices.count)"
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
                        .accessibilityLabel("Стан: \(downloadManager.statusMessage)")
                }
            }
        }
        .navigationTitle(language.nameUk)
        .onAppear { downloadManager.refreshInstalled() }
        .alert(item: $voicePendingDelete) { voice in
            Alert(
                title: Text("Видалити голос \(voice.displayName)?"),
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
                Text(voice.displayName)
                Text("\(voice.genderUk), \(voice.sizeMegabytesText)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel(voice))

            Spacer()

            if let progress = downloadManager.downloadProgress[voice.id] {
                ProgressView(value: progress)
                    .frame(width: 80)
                    .accessibilityLabel("Завантаження \(voice.displayName)")
                    .accessibilityValue("\(Int(progress * 100)) відсотків")
            } else if downloadManager.isInstalled(voice) {
                Button("Видалити") {
                    voicePendingDelete = voice
                }
                .foregroundColor(.red)
                .accessibilityLabel("Видалити голос \(voice.displayName)")
                .accessibilityHint("Голос зникне з VoiceOver, його можна буде завантажити знову.")
            } else {
                Button("Завантажити") {
                    downloadManager.download(voice, language: language)
                }
                .accessibilityLabel("Завантажити голос \(voice.displayName), \(voice.sizeMegabytesText)")
                .accessibilityHint("Після завантаження голос з'явиться у списку голосів і у VoiceOver.")
            }
        }
    }

    private func rowAccessibilityLabel(_ voice: ManifestVoice) -> String {
        var label = "\(voice.displayName), \(voice.genderUk), \(voice.sizeMegabytesText)"
        if let progress = downloadManager.downloadProgress[voice.id] {
            label += ", завантаження \(Int(progress * 100)) відсотків"
        } else if downloadManager.isInstalled(voice) {
            label += ", завантажено"
        } else {
            label += ", не завантажено"
        }
        return label
    }
}
