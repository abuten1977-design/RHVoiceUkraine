import XCTest

/// Перевіряє доставку особистого словника наголосів у папку налаштувань рушія.
/// Заведено 28.09.2026, коли з'ясувалось: доставку робило РОЗШИРЕННЯ, якому
/// запис заборонена, тому словник, найпевніше, не доходив до рушія ніколи.
final class RHVoiceEngineConfigPreparationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rhvoice-config-prep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundledData(conf: String = "languages.ukrainian.max_rate=5\n") throws -> URL {
        let dir = root.appendingPathComponent("Bundle/RHVoiceData", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(conf.utf8).write(to: dir.appendingPathComponent("RHVoice.conf"))
        return dir
    }

    private func makeContainer() throws -> URL {
        let dir = root.appendingPathComponent("Container", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func preparedDictionaryURL(in container: URL) -> URL {
        container
            .appendingPathComponent(RHVoiceEngineConfigPreparation.configDirectoryName, isDirectory: true)
            .appendingPathComponent(RHVoiceEngineConfigPreparation.dictsDirectoryName, isDirectory: true)
            .appendingPathComponent(RHVoiceEngineConfigPreparation.languageDirectoryName, isDirectory: true)
            .appendingPathComponent(PersonalUserDictionary.dictionaryFileName)
    }

    func testDeliversConfigAndPersonalDictionary() throws {
        let container = try makeContainer()
        let bundled = try makeBundledData()
        let source = container.appendingPathComponent(PersonalUserDictionary.dictionaryFileName)
        try Data("тест=те́ст\n".utf8).write(to: source)

        let outcome = try RHVoiceEngineConfigPreparation.prepare(
            containerDirectory: container,
            bundledDataDirectory: bundled,
            personalDictionarySource: source)

        XCTAssertTrue(outcome.engineConfigCopied)
        XCTAssertTrue(outcome.personalDictionaryCopied)
        let conf = outcome.configDirectory.appendingPathComponent("RHVoice.conf")
        XCTAssertEqual(try String(contentsOf: conf, encoding: .utf8), "languages.ukrainian.max_rate=5\n")
        XCTAssertEqual(try String(contentsOf: preparedDictionaryURL(in: container), encoding: .utf8), "тест=те́ст\n")
    }

    /// Рушій читає папку налаштувань, а не джерело. Тому оновлений словник
    /// має заміщати приготовану копію, інакше зміна не доїде.
    func testSecondRunOverwritesPreparedDictionary() throws {
        let container = try makeContainer()
        let bundled = try makeBundledData()
        let source = container.appendingPathComponent(PersonalUserDictionary.dictionaryFileName)
        try Data("перше=пе́рше\n".utf8).write(to: source)
        _ = try RHVoiceEngineConfigPreparation.prepare(containerDirectory: container,
                                                      bundledDataDirectory: bundled,
                                                      personalDictionarySource: source)

        try Data("друге=дру́ге\n".utf8).write(to: source)
        _ = try RHVoiceEngineConfigPreparation.prepare(containerDirectory: container,
                                                      bundledDataDirectory: bundled,
                                                      personalDictionarySource: source)

        XCTAssertEqual(try String(contentsOf: preparedDictionaryURL(in: container), encoding: .utf8), "друге=дру́ге\n")
    }

    /// Користувач видалив усі свої наголоси — приготована копія мусить піти,
    /// інакше рушій читав би словник, якого вже немає.
    func testRemovedSourceRemovesPreparedCopy() throws {
        let container = try makeContainer()
        let bundled = try makeBundledData()
        let source = container.appendingPathComponent(PersonalUserDictionary.dictionaryFileName)
        try Data("слово=сло́во\n".utf8).write(to: source)
        _ = try RHVoiceEngineConfigPreparation.prepare(containerDirectory: container,
                                                      bundledDataDirectory: bundled,
                                                      personalDictionarySource: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedDictionaryURL(in: container).path))

        try FileManager.default.removeItem(at: source)
        let outcome = try RHVoiceEngineConfigPreparation.prepare(containerDirectory: container,
                                                                bundledDataDirectory: bundled,
                                                                personalDictionarySource: source)

        XCTAssertFalse(outcome.personalDictionaryCopied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedDictionaryURL(in: container).path))
    }

    /// Папка налаштувань мусить з'явитись навіть без словника — інакше рушій
    /// не отримає `RHVoice.conf` і піде на бандл разом із межею швидкості.
    func testCreatesLayoutWithoutPersonalDictionary() throws {
        let container = try makeContainer()
        let bundled = try makeBundledData()

        let outcome = try RHVoiceEngineConfigPreparation.prepare(containerDirectory: container,
                                                                bundledDataDirectory: bundled,
                                                                personalDictionarySource: nil)

        XCTAssertTrue(outcome.engineConfigCopied)
        XCTAssertFalse(outcome.personalDictionaryCopied)
        var isDirectory: ObjCBool = false
        let languageDir = preparedDictionaryURL(in: container).deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: languageDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// Немає джерела налаштувань (бандл не знайдено) — не падаємо і не брешемо
    /// про доставку.
    func testMissingBundledDataIsReportedHonestly() throws {
        let container = try makeContainer()

        let outcome = try RHVoiceEngineConfigPreparation.prepare(containerDirectory: container,
                                                                bundledDataDirectory: nil,
                                                                personalDictionarySource: nil)

        XCTAssertFalse(outcome.engineConfigCopied)
    }
}
