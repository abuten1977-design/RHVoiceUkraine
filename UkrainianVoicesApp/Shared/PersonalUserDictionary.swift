import Foundation
import CoreFoundation

struct PersonalDictionaryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var displayWord: String
    var stressedWord: String
    var createdAt: Date
}

struct PersonalDictionaryFileStatus: Equatable {
    var dictionaryPath: String?
    var metadataPath: String?
    var dictionaryExists: Bool
    var metadataExists: Bool
    var dictionarySize: UInt64
    var metadataSize: UInt64
    var dictionaryModifiedAt: Date?
    var metadataModifiedAt: Date?
}

enum PersonalUserDictionaryError: LocalizedError, Equatable {
    case emptyDisplayWord
    case emptyStressedWord
    case appGroupUnavailable
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyDisplayWord:
            return NSLocalizedString("Поле «Слово» не може бути порожнім.", comment: "")
        case .emptyStressedWord:
            return NSLocalizedString("Поле «Слово з наголосом» не може бути порожнім.", comment: "")
        case .appGroupUnavailable:
            return NSLocalizedString("Не вдалося відкрити спільне сховище App Group.", comment: "")
        case .unreadableFile:
            return NSLocalizedString("Словник наголосів не вдалося прочитати. Щоб не втратити наявні наголоси, зміну не збережено.", comment: "")
        }
    }
}

enum PersonalUserDictionary {
    static let dictionaryFileName = "user_dictionary.txt"
    static let metadataFileName = "user_dictionary_meta.json"
    static let changeNotificationName = RHVoiceSharedSettings.personalDictionaryChangedNotificationName

    /// Читання, яке ВІДРІЗНЯЄ «файла немає» від «файл не прочитався».
    ///
    /// Урок словника замін від 14.09.2026 (збірка 231) і хвороба
    /// `project-dictionary-cache-poisoning`: поки будь-яка помилка читання
    /// мовчки давала порожній список, наступна правка перезаписувала файл
    /// ОДНИМ новим записом — усі попередні наголоси зникали без жодного слова.
    ///
    /// «Файла немає» і порожній файл — це чесний порожній успіх: втрачати нічого.
    /// А ось нечитабельний або зіпсований вміст — помилка, і зберігати поверх
    /// нього не можна.
    static func loadEntriesResult() -> Result<[PersonalDictionaryEntry], PersonalUserDictionaryError> {
        guard let url = metadataURL() else { return .failure(.appGroupUnavailable) }
        guard FileManager.default.fileExists(atPath: url.path) else { return .success([]) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadableFile) }
        guard !data.isEmpty else { return .success([]) }
        guard let entries = try? jsonDecoder.decode([PersonalDictionaryEntry].self, from: data) else {
            return .failure(.unreadableFile)
        }
        return .success(entries.sorted { $0.createdAt < $1.createdAt })
    }

    /// Для показу списку. При помилці читання віддає порожній список —
    /// екран буде порожнім, але ЗАПИС від цього не постраждає: усі три правки
    /// нижче йдуть через `loadEntriesResult()` і при помилці кидають.
    static func loadEntries() -> [PersonalDictionaryEntry] {
        (try? loadEntriesResult().get()) ?? []
    }

    static func fileStatus() -> PersonalDictionaryFileStatus {
        let dictURL = dictionaryURL()
        let metaURL = metadataURL()
        let dictAttributes = attributes(for: dictURL)
        let metaAttributes = attributes(for: metaURL)
        return PersonalDictionaryFileStatus(
            dictionaryPath: dictURL?.path,
            metadataPath: metaURL?.path,
            dictionaryExists: dictAttributes != nil,
            metadataExists: metaAttributes != nil,
            dictionarySize: fileSize(from: dictAttributes),
            metadataSize: fileSize(from: metaAttributes),
            dictionaryModifiedAt: dictAttributes?[.modificationDate] as? Date,
            metadataModifiedAt: metaAttributes?[.modificationDate] as? Date
        )
    }

    @discardableResult
    static func addEntry(displayWord: String, stressedWord: String) throws -> PersonalDictionaryEntry {
        let entry = PersonalDictionaryEntry(
            id: UUID(),
            displayWord: try normalizedDisplayWord(displayWord),
            stressedWord: try normalizedStressedWord(stressedWord),
            createdAt: Date()
        )
        var entries = try loadEntriesResult().get()
        entries.append(entry)
        try saveEntries(entries)
        return entry
    }

    static func updateEntry(id: UUID, displayWord: String, stressedWord: String) throws {
        var entries = try loadEntriesResult().get()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].displayWord = try normalizedDisplayWord(displayWord)
        entries[index].stressedWord = try normalizedStressedWord(stressedWord)
        try saveEntries(entries)
    }

    static func removeEntry(id: UUID) throws {
        let entries = try loadEntriesResult().get().filter { $0.id != id }
        try saveEntries(entries)
    }

    static func exportPath() throws -> URL {
        guard let url = dictionaryURL() else {
            throw PersonalUserDictionaryError.appGroupUnavailable
        }
        return url
    }

    private static func saveEntries(_ entries: [PersonalDictionaryEntry]) throws {
        guard let metaURL = metadataURL(),
              let dictURL = dictionaryURL() else {
            throw PersonalUserDictionaryError.appGroupUnavailable
        }
        let directory = metaURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sortedEntries = entries.sorted { $0.createdAt < $1.createdAt }
        let metaData = try jsonEncoder.encode(sortedEntries)
        try atomicWrite(metaData, to: metaURL)

        let text = sortedEntries
            .map(dictionaryLine)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let body = text.isEmpty ? "" : text + "\n"
        try atomicWrite(Data(body.utf8), to: dictURL)
        notifyDictionaryChanged()
    }

    private static func normalizedDisplayWord(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PersonalUserDictionaryError.emptyDisplayWord }
        return trimmed
    }

    private static func normalizedStressedWord(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PersonalUserDictionaryError.emptyStressedWord }
        return trimmed
    }

    static func dictionaryLine(for entry: PersonalDictionaryEntry) -> String {
        let display = entry.displayWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let stressed = entry.stressedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stressed.isEmpty else { return "" }
        guard !display.isEmpty else { return stressed }
        return "\(display)=\(stressed)"
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
        // ⭐18.09.2026: знімаємо захист файла, як це з 31.07 робить словник
        // замін (`AbbreviationDictionary.save`). Без цього файл недоступний для
        // читання, поки телефон не розблокували ПІСЛЯ перезавантаження, — а
        // голос говорить уже на екрані блокування. Саме перезавантаження назвав
        // спусковим гачком тестер (Даниїл, 16.09), і на словнику замін це
        // підтвердилось. Тут — та сама профілактика.
        #if os(iOS)
        try (url as NSURL).setResourceValue(FileProtectionType.none, forKey: .fileProtectionKey)
        #endif
    }

    private static func notifyDictionaryChanged() {
        // ⭐28.09.2026 ПОРЯДОК ВАЖЛИВИЙ: спершу доставити словник у папку
        // налаштувань рушія, ПОТІМ кинути сигнал. Робить це застосунок, бо
        // розширенню запис заборонена (див. RHVoiceEngineConfigPreparation).
        RHVoiceEngineConfigPreparation.prepareForApp()
        RHVoiceDarwinNotifications.notifyPersonalDictionaryChanged()
    }

    private static func dictionaryURL() -> URL? {
        containerURL()?.appendingPathComponent(dictionaryFileName)
    }

    private static func metadataURL() -> URL? {
        containerURL()?.appendingPathComponent(metadataFileName)
    }

    /// Тільки для тестів: підміняє теку спільного сховища. Інакше поведінку
    /// на ЗІПСОВАНОМУ файлі не перевірити — у тестовому процесі App Group
    /// недоступна, і все впиралось би в `appGroupUnavailable`.
    static var containerURLOverrideForTesting: URL?

    private static func containerURL() -> URL? {
        if let override = containerURLOverrideForTesting { return override }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)
    }

    private static func attributes(for url: URL?) -> [FileAttributeKey: Any]? {
        guard let url else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)
    }

    private static func fileSize(from attributes: [FileAttributeKey: Any]?) -> UInt64 {
        if let value = attributes?[.size] as? UInt64 {
            return value
        }
        if let value = attributes?[.size] as? NSNumber {
            return value.uint64Value
        }
        return 0
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
