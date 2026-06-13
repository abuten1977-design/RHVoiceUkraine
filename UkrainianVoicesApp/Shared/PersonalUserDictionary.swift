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

enum PersonalUserDictionaryError: LocalizedError {
    case emptyDisplayWord
    case emptyStressedWord
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyDisplayWord:
            return "Поле «Слово» не може бути порожнім."
        case .emptyStressedWord:
            return "Поле «Слово з наголосом» не може бути порожнім."
        case .appGroupUnavailable:
            return "Не вдалося відкрити спільне сховище App Group."
        }
    }
}

enum PersonalUserDictionary {
    static let dictionaryFileName = "user_dictionary.txt"
    static let metadataFileName = "user_dictionary_meta.json"
    static let changeNotificationName = RHVoiceSharedSettings.personalDictionaryChangedNotificationName

    static func loadEntries() -> [PersonalDictionaryEntry] {
        guard let url = metadataURL(),
              let data = try? Data(contentsOf: url),
              let entries = try? jsonDecoder.decode([PersonalDictionaryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.createdAt < $1.createdAt }
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
        var entries = loadEntries()
        entries.append(entry)
        try saveEntries(entries)
        return entry
    }

    static func updateEntry(id: UUID, displayWord: String, stressedWord: String) throws {
        var entries = loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].displayWord = try normalizedDisplayWord(displayWord)
        entries[index].stressedWord = try normalizedStressedWord(stressedWord)
        try saveEntries(entries)
    }

    static func removeEntry(id: UUID) throws {
        let entries = loadEntries().filter { $0.id != id }
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
            .map(\.stressedWord)
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

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    private static func notifyDictionaryChanged() {
        RHVoiceDarwinNotifications.notifyPersonalDictionaryChanged()
    }

    private static func dictionaryURL() -> URL? {
        containerURL()?.appendingPathComponent(dictionaryFileName)
    }

    private static func metadataURL() -> URL? {
        containerURL()?.appendingPathComponent(metadataFileName)
    }

    private static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)
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
