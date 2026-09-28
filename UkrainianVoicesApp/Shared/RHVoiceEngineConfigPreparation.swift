import Foundation

/// Готує папку налаштувань рушія в спільному сховищі.
///
/// НАВІЩО. Рушій RHVoice читає словники ТІЛЬКИ зі своєї папки налаштувань
/// (`config_path`), тому особистий словник наголосів треба покласти саме туди:
/// `<контейнер>/RHVoiceConfig/dicts/Ukrainian/user_dictionary.txt`, а поруч —
/// `RHVoice.conf` (у ньому, зокрема, наша межа швидкості `max_rate`, без нього
/// крива швидкості буде іншою).
///
/// ЧОМУ ЦЕ РОБИТЬ ЗАСТОСУНОК, А НЕ ГОЛОС. Розширенню заборонена БУДЬ-ЯКА
/// запис — доведено заміром 26.08.2026 (`WRITE_PROBE`: App Group, keychain,
/// власна tmp) і двічі підтверджено на пристрої (18.09 — 125 відмов,
/// 28.09 — 222 відмови). До 28.09.2026 цю папку готував МІСТ із середини
/// розширення (`RHVoicePrepareWritableConfigPath`), тобто доставка особистого
/// словника, найпевніше, не працювала ніколи. Тепер: пише застосунок, голос
/// тільки читає (`RHVoiceResolveConfigPath` у мості).
///
/// Порядок важливий: спершу приготувати файли, ПОТІМ кинути Darwin-сигнал.
/// Інакше голос перечитає старе.
enum RHVoiceEngineConfigPreparation {
    static let configDirectoryName = "RHVoiceConfig"
    static let dictsDirectoryName = "dicts"
    static let languageDirectoryName = "Ukrainian"
    static let engineConfigFileName = "RHVoice.conf"
    static let bundledDataDirectoryName = "RHVoiceData"

    struct Outcome: Equatable {
        /// Папка, яку слід віддати рушієві як `config_path`.
        let configDirectory: URL
        /// Файл налаштувань рушія на місці (без нього голос піде на бандл).
        let engineConfigCopied: Bool
        /// Особистий словник наголосів доставлений.
        let personalDictionaryCopied: Bool
    }

    enum PreparationError: Error {
        case appGroupUnavailable
        case runningInsideAppExtension
    }

    /// Ядро, яке перевіряється тестами: усі шляхи передаються знадвору.
    ///
    /// - Parameters:
    ///   - containerDirectory: корінь спільного сховища.
    ///   - bundledDataDirectory: папка `RHVoiceData` у бандлі застосунку
    ///     (джерело `RHVoice.conf`). `nil` — не копіювати.
    ///   - personalDictionarySource: файл особистого словника в корені сховища.
    ///     Немає або `nil` — приготована копія ПРИБИРАЄТЬСЯ, щоб рушій не читав
    ///     віддалений користувачем словник.
    @discardableResult
    static func prepare(containerDirectory: URL,
                        bundledDataDirectory: URL?,
                        personalDictionarySource: URL?) throws -> Outcome {
        let fileManager = FileManager.default
        let configDirectory = containerDirectory.appendingPathComponent(configDirectoryName, isDirectory: true)
        let languageDirectory = configDirectory
            .appendingPathComponent(dictsDirectoryName, isDirectory: true)
            .appendingPathComponent(languageDirectoryName, isDirectory: true)

        try fileManager.createDirectory(at: languageDirectory, withIntermediateDirectories: true)

        var engineConfigCopied = false
        let configTarget = configDirectory.appendingPathComponent(engineConfigFileName)
        if let source = bundledDataDirectory?.appendingPathComponent(engineConfigFileName),
           fileManager.fileExists(atPath: source.path) {
            try replaceFile(at: configTarget, withContentsOf: source)
            engineConfigCopied = true
        } else {
            engineConfigCopied = fileManager.fileExists(atPath: configTarget.path)
        }

        var personalDictionaryCopied = false
        let dictionaryTarget = languageDirectory
            .appendingPathComponent(PersonalUserDictionary.dictionaryFileName)
        if let source = personalDictionarySource,
           fileManager.fileExists(atPath: source.path) {
            try replaceFile(at: dictionaryTarget, withContentsOf: source)
            personalDictionaryCopied = true
        } else if fileManager.fileExists(atPath: dictionaryTarget.path) {
            try fileManager.removeItem(at: dictionaryTarget)
        }

        return Outcome(configDirectory: configDirectory,
                       engineConfigCopied: engineConfigCopied,
                       personalDictionaryCopied: personalDictionaryCopied)
    }

    /// Бойовий виклик. Кликати з ЗАСТОСУНКУ: на старті і після кожної зміни
    /// особистого словника (перед Darwin-сигналом).
    @discardableResult
    static func prepareForApp() -> Outcome? {
        guard !isRunningInsideAppExtension else {
            NSLog("USERDICT_PREP skipped: running inside app extension (writes are denied)")
            return nil
        }
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID) else {
            NSLog("USERDICT_PREP failed: app group unavailable")
            return nil
        }
        do {
            let outcome = try prepare(
                containerDirectory: container,
                bundledDataDirectory: Bundle.main.resourceURL?
                    .appendingPathComponent(bundledDataDirectoryName, isDirectory: true),
                personalDictionarySource: container
                    .appendingPathComponent(PersonalUserDictionary.dictionaryFileName))
            NSLog("USERDICT_PREP ok conf=%d personal=%d at %@",
                  outcome.engineConfigCopied ? 1 : 0,
                  outcome.personalDictionaryCopied ? 1 : 0,
                  outcome.configDirectory.path)
            return outcome
        } catch {
            NSLog("USERDICT_PREP failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// `.appex` — ознака розширення. Перевірка потрібна як запобіжник: цей код
    /// лежить у спільній папці і компілюється в обидві програми.
    static var isRunningInsideAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    private static func replaceFile(at target: URL, withContentsOf source: URL) throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: source)
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: [.atomic])
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: target)
        }
        // Знімаємо захист файла — тими самими причинами, що й у словнику замін
        // і в особистому словнику: голос говорить і на екрані блокування, а
        // захищений файл до розблокування не читається.
        #if os(iOS)
        try? (target as NSURL).setResourceValue(FileProtectionType.none, forKey: .fileProtectionKey)
        #endif
    }
}
