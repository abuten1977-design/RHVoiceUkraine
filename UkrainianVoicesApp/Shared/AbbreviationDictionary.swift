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

struct AbbreviationDictionaryFileSignature: Equatable {
    let exists: Bool
    let modificationDate: Date?
    let size: Int64
}

enum AbbreviationDictionaryError: LocalizedError, Equatable {
    case emptyAbbreviation
    case emptyReplacement
    case appGroupUnavailable
    case unreadableFile
    case fileTooLarge
    case emptyImport

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
        case .fileTooLarge:
            return "Файл словника завеликий. Максимальний розмір — 1 МБ."
        case .emptyImport:
            return "У файлі немає коректних записів. Мій словник не змінено."
        }
    }
}

enum AbbreviationDictionaryImportMode {
    case add
    case replace
}

struct AbbreviationDictionaryImportPreview {
    let entries: [AbbreviationDictionaryEntry]
    let skippedLines: Int
}

struct AbbreviationDictionaryImportSummary: Equatable {
    let added: Int
    let updated: Int
    let skipped: Int

    var spokenDescription: String {
        "Словник завантажено: додано \(added), оновлено \(updated), пропущено \(skipped)."
    }
}

enum AbbreviationDictionary {
    static let dictionaryFileName = "abbreviation_dictionary.txt"
    static let maximumImportBytes = 1_024 * 1_024
    static let maximumImportedEntries = 5_000
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
        entry("Wi-Fi", "вай-фай"), entry("GPS", "джі пі ес"), entry("SMS", "ес ем ес"),
        entry("PDF", "пе де еф"), entry("USB-C", "ю ес бе сі"),
        entry("грн", "гривні"), entry("вул.", "вулиця"), entry("буд.", "будинок"), entry("кв.", "квартира")
    ]

    static func loadEntries() -> Result<[AbbreviationDictionaryEntry], AbbreviationDictionaryError> {
        guard let url = dictionaryURL() else { return .failure(.appGroupUnavailable) }
        guard FileManager.default.fileExists(atPath: url.path) else { return .success([]) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadableFile) }
        return entries(from: data)
    }

    static func fileSignature() -> AbbreviationDictionaryFileSignature {
        guard let url = dictionaryURL(), FileManager.default.fileExists(atPath: url.path) else {
            return AbbreviationDictionaryFileSignature(exists: false, modificationDate: nil, size: 0)
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return AbbreviationDictionaryFileSignature(exists: true, modificationDate: values?.contentModificationDate, size: Int64(values?.fileSize ?? 0))
    }

    static func save(entries: [AbbreviationDictionaryEntry]) throws {
        guard let url = dictionaryURL() else { throw AbbreviationDictionaryError.appGroupUnavailable }
        let normalized = normalizedEntries(entries)
        let text = normalized.map(dictionaryLine).joined(separator: "\n")
        let body = text.isEmpty ? "" : text + "\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: url, options: [.atomic])
        try (url as NSURL).setResourceValue(FileProtectionType.none, forKey: .fileProtectionKey)
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

    static func importPreview(from data: Data) -> Result<AbbreviationDictionaryImportPreview, AbbreviationDictionaryError> {
        guard data.count <= maximumImportBytes else { return .failure(.fileTooLarge) }
        guard let text = String(data: data, encoding: .utf8) else { return .failure(.unreadableFile) }
        var entries = [AbbreviationDictionaryEntry]()
        var skipped = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let split = separatorRange(in: line) else { skipped += 1; continue }
            let left = String(line[..<split.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(line[split.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !left.isEmpty, !right.isEmpty else { skipped += 1; continue }
            if entries.contains(where: { sameKey($0.abbreviation, left) }) { skipped += 1 }
            entries.removeAll { sameKey($0.abbreviation, left) }
            entries.append(entry(left, right))
            if entries.count > maximumImportedEntries { return .failure(.fileTooLarge) }
        }
        guard !entries.isEmpty else { return .failure(.emptyImport) }
        return .success(AbbreviationDictionaryImportPreview(entries: entries, skippedLines: skipped))
    }

    static func applyImport(
        _ preview: AbbreviationDictionaryImportPreview,
        to existing: [AbbreviationDictionaryEntry],
        mode: AbbreviationDictionaryImportMode
    ) -> (entries: [AbbreviationDictionaryEntry], summary: AbbreviationDictionaryImportSummary) {
        guard case .add = mode else {
            return (preview.entries, AbbreviationDictionaryImportSummary(added: preview.entries.count, updated: 0, skipped: preview.skippedLines))
        }
        var result = normalizedEntries(existing)
        var added = 0
        var updated = 0
        for entry in preview.entries {
            if result.contains(where: { sameKey($0.abbreviation, entry.abbreviation) }) { updated += 1 } else { added += 1 }
            result.removeAll { sameKey($0.abbreviation, entry.abbreviation) }
            result.append(entry)
        }
        return (result, AbbreviationDictionaryImportSummary(added: added, updated: updated, skipped: preview.skippedLines))
    }

    static func makeExportFile(entries: [AbbreviationDictionaryEntry], now: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: now)
        let fileName = "rhvoice-скорочення-\(date).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let normalized = normalizedEntries(entries)
        let header = [
            "# RHVoice Ukrainian — словник замін",
            "# Експортовано: \(date)",
            "# Власних записів: \(normalized.count)",
            "# Формат: скорочення = заміна",
            ""
        ]
        let body = header.joined(separator: "\n") + normalized.map { "\($0.abbreviation) = \($0.replacement)" }.joined(separator: "\n") + "\n"
        try Data(body.utf8).write(to: url, options: [.atomic])
        return url
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

/// Precompiled two-regex matcher. Building it is intentionally off the speech
/// path; per utterance it executes at most two regex scans after cheap exits.
struct AbbreviationDictionaryMatcher {
    private let cyrillicRegex: NSRegularExpression?
    private let latinRegex: NSRegularExpression?
    private let cyrillicReplacements: [String: String]
    private let latinReplacements: [String: String]
    private let firstCharacters: Set<Character>
    private let minimumKeyLength: Int

    init(entries: [AbbreviationDictionaryEntry]) {
        let ordered = entries.sorted { $0.abbreviation.count > $1.abbreviation.count }
        let cyrillic = ordered.filter { !Self.containsLatin($0.abbreviation) }
        let latin = ordered.filter { Self.containsLatin($0.abbreviation) }
        cyrillicReplacements = Dictionary(uniqueKeysWithValues: cyrillic.map { ($0.abbreviation.lowercased(), $0.replacement) })
        latinReplacements = Dictionary(uniqueKeysWithValues: latin.map { ($0.abbreviation, $0.replacement) })
        firstCharacters = Set(ordered.compactMap { $0.abbreviation.first }.map { String($0).lowercased().first ?? $0 })
        minimumKeyLength = ordered.map(\.abbreviation.count).min() ?? .max
        cyrillicRegex = Self.makeRegex(keys: cyrillic.map(\.abbreviation), options: [.caseInsensitive])
        latinRegex = Self.makeRegex(keys: latin.map(\.abbreviation), options: [])
    }

    var isEmpty: Bool { minimumKeyLength == .max }

    func replace(in text: String, shouldReplace: (String, Range<String.Index>, String) -> Bool) -> String {
        guard !isEmpty, text.count >= minimumKeyLength,
              text.lowercased().contains(where: { firstCharacters.contains($0) }) else { return text }
        var result = replace(in: text, regex: cyrillicRegex, replacements: cyrillicReplacements, normalizeKey: { $0.lowercased() }, shouldReplace: shouldReplace)
        result = replace(in: result, regex: latinRegex, replacements: latinReplacements, normalizeKey: { $0 }, shouldReplace: shouldReplace)
        return result
    }

    private func replace(in text: String, regex: NSRegularExpression?, replacements: [String: String], normalizeKey: (String) -> String, shouldReplace: (String, Range<String.Index>, String) -> Bool) -> String {
        guard let regex, !replacements.isEmpty else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        return matches.reversed().reduce(into: text) { source, match in
            guard let range = Range(match.range, in: source) else { return }
            let key = String(source[range])
            guard let replacement = replacements[normalizeKey(key)], shouldReplace(key, range, source) else { return }
            source.replaceSubrange(range, with: replacement)
        }
    }

    private static func makeRegex(keys: [String], options: NSRegularExpression.Options) -> NSRegularExpression? {
        guard !keys.isEmpty else { return nil }
        let alternatives = keys.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])", options: options)
    }

    private static func containsLatin(_ value: String) -> Bool {
        value.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
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
    private var matcher = AbbreviationDictionaryMatcher(entries: AbbreviationDictionary.bundledEntries)
    private var observing = false
    private var cachedSignature = AbbreviationDictionaryFileSignature(exists: false, modificationDate: nil, size: 0)

    private init() {}

    func start() {
        lock.lock()
        let shouldStart = !observing
        observing = true
        lock.unlock()
        guard shouldStart else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.notificationCallback,
            AbbreviationDictionary.changeNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        reloadSynchronously(source: "extension-start")
    }

    func entries() -> [AbbreviationDictionaryEntry] {
        start()
        reloadIfFileChanged()
        lock.lock(); defer { lock.unlock() }
        return cachedEntries
    }

    func replace(in text: String, shouldReplace: (String, Range<String.Index>, String) -> Bool) -> String {
        start()
        reloadIfFileChanged()
        lock.lock(); let matcher = matcher; lock.unlock()
        return matcher.replace(in: text, shouldReplace: shouldReplace)
    }

    func refreshAsync() {
        queue.async { [weak self] in
            guard let self else { return }
            self.reloadNow(source: "darwin-notification")
        }
    }

    private func reloadIfFileChanged() {
        let signature = AbbreviationDictionary.fileSignature()
        lock.lock(); let changed = signature != cachedSignature; lock.unlock()
        guard changed else { return }
        reloadSynchronously(source: "signature-change")
    }

    private func reloadSynchronously(source: String) {
        let ready = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            self?.reloadNow(source: source)
            ready.signal()
        }
        _ = ready.wait(timeout: .now() + 0.3)
    }

    private func reloadNow(source: String) {
        let userEntries = (try? AbbreviationDictionary.loadEntries().get()) ?? []
        let merged = AbbreviationDictionary.mergedEntries(userEntries: userEntries)
        let signature = AbbreviationDictionary.fileSignature()
        lock.lock(); cachedEntries = merged; matcher = AbbreviationDictionaryMatcher(entries: merged); cachedSignature = signature; lock.unlock()
        NSLog("ABBREV_DICT_DIAG source=%@ bundled=%d user=%d total=%d", source, AbbreviationDictionary.bundledEntries.count, userEntries.count, merged.count)
    }

    private static let notificationCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        Unmanaged<AbbreviationDictionaryCache>.fromOpaque(observer).takeUnretainedValue().refreshAsync()
    }
}
