import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Екран «Що почув синтезатор».
///
/// Показує текст, який система віддала нашому голосу останніми разами. Потрібен,
/// щоб тестувальник міг надіслати реальний вхід, не підключаючи телефон кабелем:
/// прочитав текст у застосунку → зайшов сюди → натиснув «Скопіювати» → вставив
/// у повідомлення.
struct CapturedRequestsView: View {
    @State private var entries: [RHVoiceRequestCapture.Entry] = []
    @State private var isCaptureEnabled: Bool = RHVoiceRequestCapture.isEnabled
    @State private var statusMessage: String = ""

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return formatter
    }()

    var body: some View {
        List {
            Section("Як зробити запис") {
                Text("1. Увімкніть «Розширену діагностику» на головному екрані. 2. Прочитайте потрібний текст голосом RHVoice у будь-якому застосунку. 3. Поверніться сюди, натисніть «Оновити», потім «Скопіювати записи» і вставте їх у повідомлення розробнику.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Порядок дій: увімкнути розширену діагностику, прочитати текст голосом, повернутися сюди, оновити, скопіювати записи і надіслати розробнику.")

                Text(isCaptureEnabled ? "Запис увімкнено." : "Запис вимкнено — нові тексти не зберігаються.")
                    .font(.footnote)
                    .foregroundColor(isCaptureEnabled ? .secondary : .red)
                    .accessibilityLabel(isCaptureEnabled ? "Запис увімкнено" : "Запис вимкнено, нові тексти не зберігаються")
            }

            Section("Дії") {
                Button {
                    reload()
                } label: {
                    Label("Оновити", systemImage: "arrow.clockwise")
                }
                .accessibilityHint("Перечитує збережені записи.")

                Button {
                    copyReport()
                } label: {
                    Label("Скопіювати записи", systemImage: "doc.on.doc")
                }
                .disabled(entries.isEmpty)
                .accessibilityHint("Копіює всі записи у буфер обміну, щоб вставити їх у повідомлення.")

                Button(role: .destructive) {
                    RHVoiceRequestCapture.clear()
                    reload()
                    announce("Записи очищено")
                } label: {
                    Label("Очистити записи", systemImage: "trash")
                }
                .disabled(entries.isEmpty)
                .accessibilityHint("Стирає збережені тексти з пристрою.")

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section(entries.isEmpty ? "Записів немає" : "Записи (найновіший перший)") {
                if entries.isEmpty {
                    Text("Поки нічого не записано. Увімкніть діагностику і прочитайте будь-який текст голосом RHVoice.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateFormatter.string(from: entry.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Text("\(entry.characters) символів")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Запис від \(dateFormatter.string(from: entry.date)), \(entry.characters) символів. Текст: \(entry.text)")
                    }
                }
            }
        }
        .navigationTitle("Що почув синтезатор")
        .onAppear { reload() }
    }

    private func reload() {
        entries = RHVoiceRequestCapture.entries()
        isCaptureEnabled = RHVoiceRequestCapture.isEnabled
        statusMessage = ""
    }

    private func copyReport() {
        let report = RHVoiceRequestCapture.report(entries: entries)
        #if os(iOS)
        UIPasteboard.general.string = report
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
        statusMessage = "Скопійовано \(entries.count) записів."
        announce("Записи скопійовано")
    }

    private func announce(_ message: String) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        #endif
    }
}
