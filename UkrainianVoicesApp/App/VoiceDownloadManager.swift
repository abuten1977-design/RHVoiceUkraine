import AVFAudio
import CryptoKit
import Foundation
import ZIPFoundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Манифест завантажуваних голосів

/// Манифест лежить у GitHub-релізі нашого репозиторію разом з архівами голосів.
/// Оновлення каталогу = заміна asset'ів релізу, без оновлення застосунку.
struct VoiceManifest: Codable, Equatable {
    var formatVersion: Int
    var updated: String?
    var languages: [ManifestLanguage]
}

struct ManifestLanguage: Codable, Equatable, Identifiable {
    var id: String
    var engineName: String
    var bcp47: String
    var nameUk: String
    var nameEn: String
    var languageDataBuiltIn: Bool?
    var voices: [ManifestVoice]
}

struct ManifestVoice: Codable, Equatable, Identifiable {
    var id: String
    var engineName: String
    var displayName: String
    var gender: String
    var genderUk: String
    var version: Int
    var sizeBytes: Int64
    var sha256: String
    var url: String
    var license: String?
    var sampleText: String?

    var sizeMegabytesText: String {
        String(format: "%.1f МБ", Double(sizeBytes) / 1_048_576.0)
    }
}

// MARK: - Менеджер завантаження

@MainActor
final class VoiceDownloadManager: ObservableObject {
    static let manifestURL = URL(string: "https://github.com/abuten1977-design/RHVoiceUkraine/releases/download/voice-data-v1/manifest.json")!
    static let manifestCacheFileName = "VoiceManifestCache.json"

    enum ManifestState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published var manifest: VoiceManifest?
    @Published var manifestState: ManifestState = .idle
    @Published var installedVoiceIds: Set<String> = []
    /// Прогрес 0…1 для голосів, які саме завантажуються.
    @Published var downloadProgress: [String: Double] = [:]
    @Published var statusMessage: String = ""

    func refresh() {
        refreshInstalled()
        if manifest == nil {
            Task { await loadManifest() }
        }
    }

    func refreshInstalled() {
        let ids = RHVoiceDownloadableVoices.scanInstalledVoices().map { descriptor in
            descriptor.identifier.components(separatedBy: ".").last ?? descriptor.identifier
        }
        installedVoiceIds = Set(ids)
    }

    func isInstalled(_ voice: ManifestVoice) -> Bool {
        installedVoiceIds.contains(voice.id)
    }

    func isDownloading(_ voice: ManifestVoice) -> Bool {
        downloadProgress[voice.id] != nil
    }

    // MARK: Манифест

    func loadManifest(forceNetwork: Bool = false) async {
        manifestState = .loading
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.manifestURL)
            let decoded = try JSONDecoder().decode(VoiceManifest.self, from: data)
            manifest = decoded
            manifestState = .loaded
            Self.writeManifestCache(data)
        } catch {
            if !forceNetwork, let cached = Self.readManifestCache(),
               let decoded = try? JSONDecoder().decode(VoiceManifest.self, from: cached) {
                manifest = decoded
                manifestState = .loaded
                statusMessage = "Немає інтернету — показано збережений список голосів."
            } else {
                manifestState = .failed("Не вдалося завантажити список голосів. Перевірте інтернет і спробуйте ще раз.")
            }
        }
    }

    private static func manifestCacheURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)?
            .appendingPathComponent(manifestCacheFileName)
    }

    private static func writeManifestCache(_ data: Data) {
        guard let url = manifestCacheURL() else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func readManifestCache() -> Data? {
        guard let url = manifestCacheURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: Завантаження голосу

    func download(_ voice: ManifestVoice, language: ManifestLanguage) {
        guard !isDownloading(voice) else { return }
        downloadProgress[voice.id] = 0
        statusMessage = "Завантаження голосу \(voice.displayName)…"

        Task { [weak self] in
            do {
                try await Self.performDownload(voice: voice, language: language) { progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[voice.id] = progress
                    }
                }
                await MainActor.run { [weak self] in
                    self?.downloadProgress[voice.id] = nil
                    self?.finishVoicesChange(message: "Голос \(voice.displayName) завантажено. Тепер його можна увімкнути у VoiceOver.")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.downloadProgress[voice.id] = nil
                    self?.statusMessage = "Не вдалося завантажити голос \(voice.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    func delete(_ voice: ManifestVoice) {
        guard let dir = RHVoiceDownloadableVoices.voiceDirectoryURL(id: voice.id) else { return }
        do {
            try FileManager.default.removeItem(at: dir)
            finishVoicesChange(message: "Голос \(voice.displayName) видалено.")
        } catch {
            statusMessage = "Не вдалося видалити голос \(voice.displayName): \(error.localizedDescription)"
        }
    }

    /// Спільний фініш після download/delete: оновити кеші, повідомити движки
    /// (обидва процеси — застосунок і extension), систему, головний екран і
    /// користувача screen reader'а.
    private func finishVoicesChange(message: String) {
        refreshInstalled()
        RHVoiceDownloadedVoicesCache.shared.refreshAsync()
        RHVoiceDarwinNotifications.post(RHVoiceDownloadableVoices.downloadedVoicesChangedNotificationName)
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        NotificationCenter.default.post(name: RHVoiceDownloadableVoices.inProcessListChangedNotification, object: nil)
        statusMessage = message
        announceForScreenReader(message)
    }

    /// VoiceOver-анонс результату: без нього завершення завантаження чутно лише
    /// якщо фокус стоїть на рядку статусу.
    private func announceForScreenReader(_ message: String) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #else
        if let app = NSApp {
            NSAccessibility.post(
                element: app,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
        }
        #endif
    }

    // MARK: Робота з файлами (поза MainActor)

    enum DownloadError: LocalizedError {
        case badResponse
        case checksumMismatch
        case invalidArchive
        case appGroupUnavailable

        var errorDescription: String? {
            switch self {
            case .badResponse: return "сервер не відповів"
            case .checksumMismatch: return "файл пошкоджено при передачі"
            case .invalidArchive: return "архів голосу неповний"
            case .appGroupUnavailable: return "спільне сховище недоступне"
            }
        }
    }

    nonisolated private static func performDownload(
        voice: ManifestVoice,
        language: ManifestLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: voice.url) else { throw DownloadError.badResponse }
        guard let root = RHVoiceDownloadableVoices.voicesRootURL() else { throw DownloadError.appGroupUnavailable }

        let data = try await downloadData(from: url, expectedBytes: voice.sizeBytes, progress: progress)

        // Контрольна сума: захист від обірваної або підміненої передачі.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == voice.sha256.lowercased() else { throw DownloadError.checksumMismatch }

        let fileManager = FileManager.default
        let tmpRoot = root.deletingLastPathComponent().appendingPathComponent("tmp", isDirectory: true)
        let tmpZip = tmpRoot.appendingPathComponent("\(voice.id).zip")
        let tmpUnzip = tmpRoot.appendingPathComponent(voice.id, isDirectory: true)
        try? fileManager.removeItem(at: tmpUnzip)
        try fileManager.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try data.write(to: tmpZip, options: [.atomic])
        defer { try? fileManager.removeItem(at: tmpZip) }

        try fileManager.createDirectory(at: tmpUnzip, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: tmpZip, to: tmpUnzip)

        guard fileManager.fileExists(atPath: tmpUnzip.appendingPathComponent("voice.info").path) else {
            try? fileManager.removeItem(at: tmpUnzip)
            throw DownloadError.invalidArchive
        }

        // meta.json — щоб сканер знав мову/ім'я без повторного парсингу манифеста.
        let meta = RHVoiceDownloadableVoices.DownloadedVoiceMeta(
            id: voice.id,
            engineName: voice.engineName,
            displayName: voice.displayName,
            language: language.bcp47,
            gender: voice.gender,
            version: voice.version,
            sampleText: voice.sampleText ?? "Hello! This is the \(voice.displayName) voice."
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: tmpUnzip.appendingPathComponent(RHVoiceDownloadableVoices.metaFileName), options: [.atomic])

        removeFileProtection(at: tmpUnzip)

        // Атомарна заміна: спершу все готуємо у tmp, потім переносимо на місце.
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(voice.id, isDirectory: true)
        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: tmpUnzip, to: target)
    }

    nonisolated private static func downloadData(
        from url: URL,
        expectedBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DownloadError.badResponse
        }
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : expectedBytes
        var data = Data()
        if total > 0 { data.reserveCapacity(Int(total)) }
        var received: Int64 = 0
        for try await byte in bytes {
            data.append(byte)
            received += 1
            if total > 0, received % 262_144 == 0 {
                progress(min(0.99, Double(received) / Double(total)))
            }
        }
        progress(1.0)
        return data
    }

    /// Extension має читати дані голосу і на заблокованому екрані —
    /// знімаємо FileProtection з усього дерева (як у польському застосунку).
    nonisolated private static func removeFileProtection(at url: URL) {
        #if os(iOS)
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.none]
        try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in enumerator {
                try? fileManager.setAttributes(attributes, ofItemAtPath: item.path)
            }
        }
        #endif
    }
}
