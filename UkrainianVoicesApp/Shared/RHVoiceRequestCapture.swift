import Foundation

/// Запис останніх текстів, які VoiceOver надіслав синтезатору.
///
/// Навіщо: у різних застосунках (і навіть у тій самій нотатці — у режимі
/// редагування чи вже збереженій) iOS сама розбирає номери, час і дати, тож до
/// нас текст може дійти вже зміненим. Поки ми не бачимо реального входу, будь-яке
/// виправлення читання буде наосліп.
///
/// Чому не файл: `RHVoiceDebug.log` із extension на iOS недоступний. Обмін іде
/// через спільні `UserDefaults` App Group — той самий канал, яким extension уже
/// читає налаштування, тобто перевірено робочий.
///
/// Запис вмикається перемикачем «Розширена діагностика» і за замовчуванням
/// вимкнений: коли він вимкнений, вартість — одне читання прапорця на запит.
/// Тексти лишаються на пристрої й нікуди не надсилаються.
enum RHVoiceRequestCapture {
    static let storageKey = "capturedSpeechRequests"
    static let maxEntries = 5
    static let maxTextLength = 4000

    struct Entry: Codable, Identifiable, Equatable {
        let date: Date
        let voiceId: String
        let characters: Int
        let text: String

        var id: Date { date }
    }

    private static let defaults = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)
    private static let queue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.requestCapture", qos: .utility)

    static var isEnabled: Bool {
        defaults?.bool(forKey: RHVoiceSharedSettings.extendedDiagnosticsKey) ?? false
    }

    /// Викликається з `synthesizeSpeechRequest`. Нічого не робить, поки діагностика
    /// вимкнена; сам запис — асинхронно, щоб не додавати затримки до синтезу.
    static func record(text: String, voiceId: String) {
        guard isEnabled else { return }
        let entry = Entry(
            date: Date(),
            voiceId: voiceId,
            characters: text.count,
            text: String(text.prefix(maxTextLength))
        )
        queue.async {
            guard let defaults = defaults else { return }
            var stored = decode(defaults.data(forKey: storageKey))
            stored.insert(entry, at: 0)
            if stored.count > maxEntries {
                stored = Array(stored.prefix(maxEntries))
            }
            if let data = try? JSONEncoder().encode(stored) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    static func entries() -> [Entry] {
        decode(defaults?.data(forKey: storageKey))
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }

    /// Готовий до пересилання текст: усе, що записалось, одним шматком.
    static func report(entries: [Entry]) -> String {
        guard !entries.isEmpty else { return "Записів немає." }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return entries.enumerated().map { index, entry in
            """
            Запис \(index + 1) — \(formatter.string(from: entry.date))
            Голос: \(entry.voiceId)
            Довжина: \(entry.characters) символів
            Текст:
            \(entry.text)
            """
        }.joined(separator: "\n\n———\n\n")
    }

    private static func decode(_ data: Data?) -> [Entry] {
        guard let data = data else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
