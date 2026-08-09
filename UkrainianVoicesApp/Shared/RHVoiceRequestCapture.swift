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

    private static let queue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.requestCapture", qos: .utility)

    /// Ключі «слідів»: пишуться навіть коли текст не зберігаємо, щоб було видно,
    /// чи взагалі жива діагностика в extension і чи доходять до нього запити.
    static let lastRequestDateKey = "captureLastRequestDate"
    static let lastRequestCharsKey = "captureLastRequestChars"
    static let requestCountKey = "captureRequestCount"
    static let lastWriteErrorKey = "captureLastWriteError"

    /// ЩОРАЗУ свіжий примірник: `UserDefaults` кешує значення в межах процесу,
    /// а тут два процеси (застосунок і extension) пишуть і читають по черзі.
    /// Саме через кеш збірка 214 показувала «записів немає»: extension бачив
    /// старе значення перемикача, а застосунок — старий список.
    private static var store: UserDefaults? {
        let defaults = UserDefaults(suiteName: RHVoiceSharedSettings.appGroupID)
        defaults?.synchronize()
        return defaults
    }

    static var isEnabled: Bool {
        store?.bool(forKey: RHVoiceSharedSettings.extendedDiagnosticsKey) ?? false
    }

    /// Викликається з `synthesizeSpeechRequest`. Слід (дата, довжина, лічильник)
    /// пишеться завжди — це дешево і не містить тексту. Сам текст — лише коли
    /// увімкнена «Розширена діагностика».
    static func record(text: String, voiceId: String) {
        let now = Date()
        let length = text.count
        let enabled = isEnabled
        let snippet = enabled ? String(text.prefix(maxTextLength)) : nil
        queue.async {
            guard let defaults = store else { return }
            defaults.set(now, forKey: lastRequestDateKey)
            defaults.set(length, forKey: lastRequestCharsKey)
            defaults.set(defaults.integer(forKey: requestCountKey) + 1, forKey: requestCountKey)
            if let snippet = snippet {
                append(Entry(date: now, voiceId: voiceId, characters: length, text: snippet), to: defaults)
            }
            defaults.synchronize()
        }
    }

    /// Пробний запис із самого застосунку. Якщо він з'являється у списку, а
    /// записів від голосу немає — значить проблема саме в extension, а не в
    /// показі списку.
    static func writeTestEntry() {
        guard let defaults = store else { return }
        append(Entry(date: Date(),
                     voiceId: "перевірка з застосунку",
                     characters: 0,
                     text: "Пробний запис. Якщо ви його бачите, показ списку працює."),
               to: defaults)
        defaults.synchronize()
    }

    private static func append(_ entry: Entry, to defaults: UserDefaults) {
        var stored = decode(defaults.data(forKey: storageKey))
        stored.insert(entry, at: 0)
        if stored.count > maxEntries {
            stored = Array(stored.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.set("не вдалося закодувати запис", forKey: lastWriteErrorKey)
        }
    }

    static func entries() -> [Entry] {
        decode(store?.data(forKey: storageKey))
    }

    /// Слід останнього звернення голосу до синтезатора: дата, довжина, лічильник.
    static func trace() -> (date: Date?, characters: Int, count: Int) {
        guard let defaults = store else { return (nil, 0, 0) }
        return (defaults.object(forKey: lastRequestDateKey) as? Date,
                defaults.integer(forKey: lastRequestCharsKey),
                defaults.integer(forKey: requestCountKey))
    }

    static func clear() {
        guard let defaults = store else { return }
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: lastRequestDateKey)
        defaults.removeObject(forKey: lastRequestCharsKey)
        defaults.removeObject(forKey: requestCountKey)
        defaults.synchronize()
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
