import Foundation

/// Завантажувані голоси (не вбудовані в бандл). Дані лежать в App Group:
/// <container>/DownloadedVoices/voices/<id>/ — розпакований голос RHVoice
/// (voice.info, voice.params, 16000/, 24000/) плюс наш meta.json.
/// Движок підхоплює їх через params.resource_paths (офіційний механізм RHVoice),
/// тому пересборка бандла не потрібна — лише переініціалізація движка.
enum RHVoiceDownloadableVoices {
    static let rootFolderName = "DownloadedVoices"
    static let voicesSubfolder = "voices"
    static let metaFileName = "meta.json"
    /// Darwin-нотифікація: склад завантажених голосів змінився (download/delete).
    /// Слухають: обидва мости RHVoiceEngine (переініціалізація движка)
    /// і кеш списку голосів у extension.
    static let downloadedVoicesChangedNotificationName = "com.rhvoice.UkrainianVoices.downloadedVoicesChanged"
    /// Внутрішньопроцесна нотифікація для UI застосунку: оновити список голосів
    /// на головному екрані одразу після download/delete (без перезапуску).
    static let inProcessListChangedNotification = Notification.Name("RHVoiceDownloadedVoicesListChanged")

    /// name= із voice.info → BCP-47 код для AVSpeechSynthesisProviderVoice.
    static let engineLanguageToBCP47: [String: String] = [
        "English": "en-US"
    ]

    /// Internal CMU voice IDs are not useful when VoiceOver reads them aloud.
    /// Keep engine `profileName` unchanged; this map is only for user-visible
    /// labels and is also applied to previously downloaded meta.json files.
    ///
    /// ⭐LATIN, NOT CYRILLIC (measured by ear 2026-09-14, build 230, iPhone 12
    /// iOS 26.6.1). In the VoiceOver rotor the voice name is spoken by THAT
    /// voice itself, and an English CMU voice cannot read Cyrillic — so
    /// «Бен» came out as silence and the user heard an unnamed, blank entry.
    /// In Settings → VoiceOver → Speech the same name reads fine, because
    /// there the Ukrainian voice announces it. Ostap reported the same blank
    /// rotor entry on 2026-08-31 (build 222) on a different device.
    /// Decision by Andriy 2026-09-14: Latin everywhere — the app screen and
    /// the system voice list must show ONE name, not two.
    static let humanReadableNames: [String: String] = [
        "bdl": "Ben",
        "clb": "Clara",
        "slt": "Sarah",
        "ksp": "Raj"
    ]

    static func userFacingName(id: String, fallback: String) -> String {
        humanReadableNames[id.lowercased()] ?? fallback
    }

    struct DownloadedVoiceMeta: Codable, Equatable {
        var id: String
        var engineName: String
        var displayName: String
        var language: String      // BCP-47, напр. "en-US"
        var gender: String        // "male" | "female"
        var version: Int
        var sampleText: String
    }

    static func voicesRootURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)?
            .appendingPathComponent(rootFolderName, isDirectory: true)
            .appendingPathComponent(voicesSubfolder, isDirectory: true)
    }

    static func voiceDirectoryURL(id: String) -> URL? {
        voicesRootURL()?.appendingPathComponent(id, isDirectory: true)
    }

    /// Сканує App Group і повертає дескриптори всіх коректно встановлених голосів.
    /// Голос вважається встановленим, якщо в його папці є voice.info.
    static func scanInstalledVoices(fileManager: FileManager = .default, rootOverride: URL? = nil) -> [RHVoiceVoiceDescriptor] {
        guard let root = rootOverride ?? voicesRootURL(),
              let entries = try? fileManager.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var result: [RHVoiceVoiceDescriptor] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let infoURL = entry.appendingPathComponent("voice.info")
            guard fileManager.fileExists(atPath: infoURL.path) else { continue }

            if let descriptor = descriptor(forVoiceDirectory: entry, infoURL: infoURL) {
                result.append(descriptor)
            }
        }
        return result
    }

    /// Коротка «довідка» про склад завантажених голосів: скільки їх, як звуться
    /// і коли востаннє змінювалися їхні теки.
    ///
    /// НАВІЩО. Рушій читає `resource_paths` ЛИШЕ на init, тож про новий голос
    /// йому треба сказати окремо. Досі єдиним способом була одноразова
    /// Darwin-нотифікація `downloadedVoicesChanged`, а вона не доходить до
    /// ЗАМОРОЖЕНОГО процесу розширення і в чергу не стає (розбір 31.08.2026,
    /// борг «англійський голос мовчить до ДРУГОГО перезавантаження»).
    /// З довідкою міст помічає зміну САМ і від сигналу більше не залежить.
    ///
    /// ДЕШЕВО НАВМИСНО: один лістинг невеликої теки, без читання даних голосу.
    ///
    /// ЗБІЙ ≠ «ГОЛОСИ ЗНИКЛИ». Якщо теку не вдалося прочитати, повертаємо окреме
    /// `unreadable`, а не порожній список — інакше помилка читання виглядала б як
    /// зміна складу і викликала переініціалізацію (урок словника замін, збірка 232).
    static func installedVoicesSignature(fileManager: FileManager = .default, rootOverride: URL? = nil) -> String {
        guard let root = rootOverride ?? voicesRootURL() else { return "no-app-group" }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "none"
        }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "unreadable"
        }

        var parts: [String] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }
            // Той самий критерій «голос встановлено», що й у scanInstalledVoices:
            // напіврозпакована тека не рахується, а коли розпакування добіжить —
            // довідка зміниться ще раз, і рушій підхопить голос.
            guard fileManager.fileExists(atPath: entry.appendingPathComponent("voice.info").path) else { continue }
            let stamp = values?.contentModificationDate.map { Int($0.timeIntervalSince1970) } ?? 0
            parts.append("\(entry.lastPathComponent)@\(stamp)")
        }
        return "\(parts.count):\(parts.joined(separator: ","))"
    }

    private static func descriptor(forVoiceDirectory directory: URL, infoURL: URL) -> RHVoiceVoiceDescriptor? {
        let dirId = directory.lastPathComponent
        let identifier = "com.rhvoice.UkrainianVoices.\(dirId)"

        if let metaData = try? Data(contentsOf: directory.appendingPathComponent(metaFileName)),
           let meta = try? JSONDecoder().decode(DownloadedVoiceMeta.self, from: metaData) {
            return RHVoiceVoiceDescriptor(
                name: userFacingName(id: dirId, fallback: meta.displayName),
                identifier: identifier,
                language: meta.language,
                profileName: meta.engineName,
                sampleText: meta.sampleText
            )
        }

        // Фолбэк без meta.json: читаємо voice.info (формат key=value).
        guard let info = try? String(contentsOf: infoURL, encoding: .utf8) else { return nil }
        var engineName: String?
        var engineLanguage: String?
        for line in info.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0].trimmingCharacters(in: .whitespaces) {
            case "name": engineName = parts[1].trimmingCharacters(in: .whitespaces)
            case "language": engineLanguage = parts[1].trimmingCharacters(in: .whitespaces)
            default: break
            }
        }
        guard let name = engineName, !name.isEmpty else { return nil }
        let bcp47 = engineLanguage.flatMap { engineLanguageToBCP47[$0] } ?? "en-US"
        return RHVoiceVoiceDescriptor(
            name: userFacingName(id: dirId, fallback: name),
            identifier: identifier,
            language: bcp47,
            profileName: name,
            sampleText: "Hello! This is the \(name) voice."
        )
    }
}

/// Кеш списку завантажених голосів для extension: сам скан робить файловий I/O
/// (containerURL/stat), який на macOS 26 може зависати (урок task-082/086),
/// тому гарячі шляхи (speechVoices, resolve голосу) читають лише кешоване
/// значення, а рескан іде асинхронно на фоновій черзі — при старті та за
/// Darwin-нотифікацією про зміну складу голосів.
final class RHVoiceDownloadedVoicesCache {
    static let shared = RHVoiceDownloadedVoicesCache()

    private let queue = DispatchQueue(label: "com.rhvoice.UkrainianVoices.downloaded-voices-cache", qos: .utility)
    private let lock = NSLock()
    private var cached: [RHVoiceVoiceDescriptor] = []
    private var started = false
    private var hasLoadedOnce = false

    func start() {
        lock.lock()
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else { return }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<RHVoiceDownloadedVoicesCache>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                    .refreshAsync()
            },
            RHVoiceDownloadableVoices.downloadedVoicesChangedNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        refreshAsync()
    }

    func currentVoices() -> [RHVoiceVoiceDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Перше звернення чекає на реальний скан (обмежено timeout), інакше система
    /// встигає спитати speechVoices ДО завершення асинхронного завантаження кеша
    /// і «не бачить» завантажені голоси (корінь бага build 191). Далі — без
    /// блокувань: на зависшому контейнері (macOS 26) wait закінчується таймаутом
    /// і повертається останнє відоме значення.
    func currentVoicesEnsuringFirstLoad(timeout: TimeInterval = 0.3) -> [RHVoiceVoiceDescriptor] {
        lock.lock()
        let loaded = hasLoadedOnce
        lock.unlock()
        guard !loaded else { return currentVoices() }

        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            guard let self else { semaphore.signal(); return }
            let voices = RHVoiceDownloadableVoices.scanInstalledVoices()
            self.lock.lock()
            self.cached = voices
            self.hasLoadedOnce = true
            self.lock.unlock()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return currentVoices()
    }

    func refreshAsync() {
        queue.async { [weak self] in
            guard let self else { return }
            let voices = RHVoiceDownloadableVoices.scanInstalledVoices()
            self.lock.lock()
            self.cached = voices
            self.hasLoadedOnce = true
            self.lock.unlock()
        }
    }
}
