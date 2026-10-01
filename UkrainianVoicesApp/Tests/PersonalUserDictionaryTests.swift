import XCTest

final class PersonalUserDictionaryTests: XCTestCase {
    func testDictionaryLineWritesDisplayEqualsStressedWord() {
        let entry = PersonalDictionaryEntry(
            id: UUID(),
            displayWord: "листопад",
            stressedWord: "лист+опад",
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(PersonalUserDictionary.dictionaryLine(for: entry), "листопад=лист+опад")
    }

    func testDictionaryLineSupportsReplacementPhrases() {
        let entry = PersonalDictionaryEntry(
            id: UUID(),
            displayWord: "кіт",
            stressedWord: "собака",
            createdAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(PersonalUserDictionary.dictionaryLine(for: entry), "кіт=собака")
    }

    func testDictionaryLineKeepsStressMarkerForTask209Scenario() {
        let entry = PersonalDictionaryEntry(
            id: UUID(),
            displayWord: "листопад",
            stressedWord: "листоп+ад",
            createdAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(PersonalUserDictionary.dictionaryLine(for: entry), "листопад=листоп+ад")
    }

    // MARK: - Захист від тихої втрати наголосів (борг 30.09.2026, зроблено 01.10.2026)
    //
    // Хвороба: будь-яка помилка читання `user_dictionary_meta.json` мовчки
    // давала порожній список, і НАСТУПНА правка перезаписувала файл одним
    // новим записом — усі попередні наголоси зникали без жодного слова.
    // Та сама хвороба, яку в словнику замін вилікували 14.09.2026.

    private func makeTemporaryContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-dict-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        PersonalUserDictionary.containerURLOverrideForTesting = url
        return url
    }

    override func tearDown() {
        PersonalUserDictionary.containerURLOverrideForTesting = nil
        super.tearDown()
    }

    func testMissingFileIsHonestEmptySuccess() throws {
        _ = try makeTemporaryContainer()

        let result = PersonalUserDictionary.loadEntriesResult()

        XCTAssertEqual(try result.get(), [], "Файла немає — втрачати нічого, це чесний порожній успіх")
    }

    func testEmptyFileIsHonestEmptySuccess() throws {
        let container = try makeTemporaryContainer()
        try Data().write(to: container.appendingPathComponent(PersonalUserDictionary.metadataFileName))

        let result = PersonalUserDictionary.loadEntriesResult()

        XCTAssertEqual(try result.get(), [])
    }

    func testCorruptedFileIsFailureNotEmptyList() throws {
        let container = try makeTemporaryContainer()
        try Data("{ це не JSON".utf8)
            .write(to: container.appendingPathComponent(PersonalUserDictionary.metadataFileName))

        let result = PersonalUserDictionary.loadEntriesResult()

        switch result {
        case .success(let entries):
            XCTFail("Зіпсований файл не можна вважати порожнім списком, прийшло \(entries.count) записів")
        case .failure(let error):
            XCTAssertEqual(error, .unreadableFile)
        }
    }

    func testAddEntryRefusesToSaveOverCorruptedFileAndKeepsItIntact() throws {
        let container = try makeTemporaryContainer()
        let metaURL = container.appendingPathComponent(PersonalUserDictionary.metadataFileName)
        let corrupted = Data("{ обірваний запис".utf8)
        try corrupted.write(to: metaURL)

        XCTAssertThrowsError(
            try PersonalUserDictionary.addEntry(displayWord: "завжди", stressedWord: "завжд+и"),
            "Поверх нечитабельного словника зберігати не можна — саме так зникали наголоси"
        ) { error in
            XCTAssertEqual(error as? PersonalUserDictionaryError, .unreadableFile)
        }

        XCTAssertEqual(try Data(contentsOf: metaURL), corrupted, "Файл мусить лишитись недоторканим")
    }

    func testRemoveEntryRefusesToSaveOverCorruptedFile() throws {
        let container = try makeTemporaryContainer()
        let metaURL = container.appendingPathComponent(PersonalUserDictionary.metadataFileName)
        try Data("[{ обірваний".utf8).write(to: metaURL)

        XCTAssertThrowsError(try PersonalUserDictionary.removeEntry(id: UUID())) { error in
            XCTAssertEqual(error as? PersonalUserDictionaryError, .unreadableFile)
        }
    }

    func testUpdateEntryRefusesToSaveOverCorruptedFile() throws {
        let container = try makeTemporaryContainer()
        let metaURL = container.appendingPathComponent(PersonalUserDictionary.metadataFileName)
        try Data("не json зовсім".utf8).write(to: metaURL)

        XCTAssertThrowsError(
            try PersonalUserDictionary.updateEntry(id: UUID(), displayWord: "кіт", stressedWord: "к+іт")
        ) { error in
            XCTAssertEqual(error as? PersonalUserDictionaryError, .unreadableFile)
        }
    }
}
