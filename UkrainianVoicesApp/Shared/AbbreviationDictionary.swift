import CoreFoundation
import Foundation

/// A plain-text replacement dictionary, deliberately separate from RHVoice's
/// stress dictionary. It expands whole abbreviations before text reaches the
/// engine; it never contains number-dependent grammar.
struct AbbreviationDictionaryEntry: Codable, Identifiable, Equatable {
    let abbreviation: String
    let replacement: String

    var id: String { abbreviation }
}

enum AbbreviationDictionaryError: LocalizedError, Equatable {
    case emptyAbbreviation
    case emptyReplacement
    case appGroupUnavailable
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyAbbreviation:
            return "Поле «Скорочення» не може бути порожнім."
        case .emptyReplacement:
            return "Поле «Як читати» не може бути порожнім."
        case .appGroupUnavailable:
            return "Не вдалося відкрити спільне сховище App Group."
        case .unreadableFile:
            return "Файл словника не вдалося прочитати. Працює базовий словник."
        }
    }
}

enum AbbreviationDictionary {
    static let dictionaryFileName = "abbreviation_dictionary.txt"
    static let changeNotificationName = RHVoiceSharedSettings.abbreviationDictionaryChangedNotificationName

    /// The resource is also included in both app bundles for people who want a
    /// visible shipped example. This immutable fallback means a damaged bundle
    /// or App Group can never silence the speech provider.
    static let bundledEntries: [AbbreviationDictionaryEntry] = [
        entry("пн", "понеділок"), entry("вт", "вівторок"), entry("ср", "середа"),
        entry("чт", "четвер"), entry("пт", "п'ятниця"), entry("сб", "субота"), entry("нд", "неділя"),
        entry("січ.", "січня"), entry("лют.", "лютого"), entry("бер.", "березня"),
        entry("квіт.", "квітня"), entry("трав.", "травня"), entry("черв.", "червня"),
        entry("лип.", "липня"), entry("серп.", "серпня"), entry("вер.", "вересня"),
        entry("жовт.", "жовтня"), entry("лист.", "листопада"), entry("груд.", "грудня"),
        entry("LTE", "ел те е"), entry("VPN", "ве пе ен"), entry("USB", "ю ес бе"),
        entry("Wi-Fi", "вай фай"), entry("GPS", "джі пі ес"), entry("SMS", "ес ем ес"),
        entry("PDF", "пе де еф"), entry("USB-C", "ю ес бе сі"),
        entry("грн", "гривні"), entry("вул.", "вулиця"), entry("буд.", "будинок"), entry("кв.", "квартира")
    ]

    static func loadEntries() -> Result<[AbbreviationDictionaryEntry], AbbreviationDictionaryError> {
        guard let url = dictionaryURL() else { return .failure(.appGroupUnavailable) }
        guard FileManager.default.fileExists(atPath: url.path) else { return .success([]) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadableFile) }
        return entries(from: data)
    }

    static func save(entries: [AbbreviationDictionaryEntry]) throws {
        guard let url = dictionaryURL() else { throw AbbreviationDictionaryError.appGroupUnavailable }
        let normalized = normalizedEntries(entries)
        let text = normalized.map(dictionaryLine).joined(separator: "\n")
        let body = text.isEmpty ? "" : text + "\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: url, options: [.atomic])
        RHVoiceDarwinNotifications.notifyAbbreviationDictionaryChanged()
    }

    static func addEntry(abbreviation: String, replacement: String) throws {
        var entries = try loadEntries().get()
        let entry = try validatedEntry(abbreviation: abbreviation, replacement: replacement)
        entries.removeAll { sameKey($0.abbreviation, entry.abbreviation) }
        entries.append(entry)
        try save(entries: entries)
    }

    static func updateEntry(oldAbbreviation: String, abbreviation: String, replacement: String) throws {
        var entries = try loadEntries().get()
        let entry = try validatedEntry(abbreviation: abbreviation, replacement: replacement)
        entries.removeAll { sameKey($0.abbreviation, oldAbbreviation) || sameKey($0.abbreviation, entry.abbreviation) }
        entries.append(entry)
        try save(entries: entries)
    }

    static func removeEntry(abbreviation: String) throws {
        var entries = try loadEntries().get()
        entries.removeAll { sameKey($0.abbreviation, abbreviation) }
        try save(entries: entries)
    }

    static func parse(text: String) -> [AbbreviationDictionaryEntry] {
        var result = [AbbreviationDictionaryEntry]()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let split = separatorRange(in: line) else { continue }
            let left = String(line[..<split.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(line[split.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !left.isEmpty, !right.isEmpty else { continue }
            result.removeAll { sameKey($0.abbreviation, left) }
            result.append(entry(left, right))
        }
        return result
    }

    static func entries(from data: Data) -> Result<[AbbreviationDictionaryEntry], AbbreviationDictionaryError> {
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.unreadableFile) }
        return .success(parse(text: text))
    }

    static func mergedEntries(userEntries: [AbbreviationDictionaryEntry]) -> [AbbreviationDictionaryEntry] {
        var merged = bundledEntries
        for entry in normalizedEntries(userEntries) {
            merged.removeAll { sameKey($0.abbreviation, entry.abbreviation) }
            merged.append(entry)
        }
        return merged
    }

    static func dictionaryLine(for entry: AbbreviationDictionaryEntry) -> String {
        "\(entry.abbreviation)\t\(entry.replacement)"
    }

    private static func validatedEntry(abbreviation: String, replacement: String) throws -> AbbreviationDictionaryEntry {
        let left = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else { throw AbbreviationDictionaryError.emptyAbbreviation }
        guard !right.isEmpty else { throw AbbreviationDictionaryError.emptyReplacement }
        return entry(left, right)
    }

    private static func normalizedEntries(_ entries: [AbbreviationDictionaryEntry]) -> [AbbreviationDictionaryEntry] {
        var result = [AbbreviationDictionaryEntry]()
        for entry in entries {
            guard let valid = try? validatedEntry(abbreviation: entry.abbreviation, replacement: entry.replacement) else { continue }
            result.removeAll { sameKey($0.abbreviation, valid.abbreviation) }
            result.append(valid)
        }
        return result
    }

    private static func separatorRange(in line: String) -> Range<String.Index>? {
        if let tab = line.range(of: "\t") { return tab }
        if let arrow = line.range(of: "=>") { return arrow }
        return line.range(of: "=")
    }

    private static func sameKey(_ lhs: String, _ rhs: String) -> Bool {
        containsLatin(lhs) || containsLatin(rhs) ? lhs == rhs : lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func containsLatin(_ value: String) -> Bool {
        value.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
    }

    private static func entry(_ abbreviation: String, _ replacement: String) -> AbbreviationDictionaryEntry {
        AbbreviationDictionaryEntry(abbreviation: abbreviation, replacement: replacement)
    }

    private static func dictionaryURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)?
            .appendingPathComponent(dictionaryFileName)
    }
}

/// The provider only reads an in-memory snapshot on the speech path. A Darwin
/// notification schedules App Group I/O in the background, so a bad container
/// cannot freeze VoiceOver and an updated dictionary applies without restart.
final class AbbreviationDictionaryCache {
    static let shared = AbbreviationDictionaryCache()

    private let queue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.abbreviation-dictionary", qos: .utility)
    private let lock = NSLock()
    private var cachedEntries = AbbreviationDictionary.bundledEntries
    private var observing = false

    private init() {}

    func entries() -> [AbbreviationDictionaryEntry] {
        start()
        lock.lock(); defer { lock.unlock() }
        return cachedEntries
    }

    func refreshAsync() {
        queue.async { [weak self] in
            guard let self else { return }
            let userEntries = (try? AbbreviationDictionary.loadEntries().get()) ?? []
            let merged = AbbreviationDictionary.mergedEntries(userEntries: userEntries)
            self.lock.lock()
            self.cachedEntries = merged
            self.lock.unlock()
        }
    }

    private func start() {
        guard !observing else { return }
        observing = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.notificationCallback,
            AbbreviationDictionary.changeNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        refreshAsync()
    }

    private static let notificationCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        Unmanaged<AbbreviationDictionaryCache>.fromOpaque(observer).takeUnretainedValue().refreshAsync()
    }
}
