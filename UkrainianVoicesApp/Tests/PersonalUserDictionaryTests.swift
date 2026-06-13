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
}
