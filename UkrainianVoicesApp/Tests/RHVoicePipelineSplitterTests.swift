import XCTest

final class RHVoicePipelineSplitterTests: XCTestCase {
    func testPlainTextSplitsIntoSentenceFragments() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "Перше речення. Друге речення. Третє речення."
        )

        XCTAssertGreaterThan(fragments.count, 1)
        XCTAssertTrue(fragments.allSatisfy { $0.hasPrefix("<speak>") && $0.hasSuffix("</speak>") })
    }

    func testSpeakAndProsodyWrappersAreReplicated() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak><prosody rate=\"fast\">Перше речення. Друге речення.</prosody></speak>"
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(RHVoicePipelineSplitter.textCharacterCount(in: fragments[0]), "Перше речення.".count)
        XCTAssertEqual(RHVoicePipelineSplitter.textCharacterCount(in: fragments[1]), "Друге речення.".count)
    }

    func testUnknownTagsAreStrippedKeepingInnerText() {
        // Engine rejects unknown tags -> per-fragment plain-text fallback with a
        // different rate formula (build 152 mixed-speed regression). Tags must be
        // dropped, their inner text preserved.
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak><p>Перше речення. Друге речення.</p><say-as interpret-as=\"characters\">АБВ</say-as>.</speak>"
        )

        XCTAssertGreaterThan(fragments.count, 1)
        let joined = fragments.joined()
        XCTAssertTrue(joined.contains("Перше речення."))
        XCTAssertTrue(joined.contains("АБВ"))
        XCTAssertFalse(joined.contains("<p>"))
        XCTAssertFalse(joined.contains("</p>"))
        XCTAssertFalse(joined.contains("<say-as"))
        XCTAssertTrue(fragments.allSatisfy { $0.hasPrefix("<speak>") && $0.hasSuffix("</speak>") })
    }

    func testShortTextWithUnknownTagReturnsCleanSpeakFragment() {
        // Short texts must take the same cleaned path as split fragments,
        // otherwise short and long texts get different rate formulas.
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak><voice name=\"x\">Коротка фраза</voice></speak>"
        )

        XCTAssertEqual(fragments.count, 1)
        XCTAssertFalse(fragments[0].contains("<voice"))
        XCTAssertTrue(fragments[0].contains("Коротка фраза"))
        XCTAssertTrue(fragments[0].hasPrefix("<speak>"))
        XCTAssertTrue(fragments[0].hasSuffix("</speak>"))
    }

    func testShortPlainTextIsWrappedInSpeak() {
        XCTAssertEqual(
            RHVoicePipelineSplitter.sentencePipelineFragments(from: "Привіт"),
            ["<speak>Привіт</speak>"]
        )
    }

    func testBreakTagsStayInsideFragments() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak>Перше речення.<break time=\"250ms\"/> Друге речення.</speak>"
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments[0].contains("Перше речення."))
        XCTAssertTrue(fragments.joined().contains("<break time=\"250ms\"/>"))
        XCTAssertTrue(fragments[1].contains("Друге речення."))
    }

    func testLongTextWithManySentencesSplits() {
        let sentences = (1...6).map { "Це довге тестове речення номер \($0), яке має достатньо слів для перевірки." }
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: "<speak>\(sentences.joined(separator: " "))</speak>")

        XCTAssertGreaterThanOrEqual(fragments.count, 6)
        XCTAssertLessThan(RHVoicePipelineSplitter.textCharacterCount(in: fragments[0]), 80)
    }

    func testDecimalNumbersAreNotSentenceBoundaries() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak>Версія 3.14 працює стабільно. Наступне речення звучить окремо.</speak>"
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments[0].contains("3.14"))
        XCTAssertEqual(RHVoicePipelineSplitter.textCharacterCount(in: fragments[0]), "Версія 3.14 працює стабільно.".count)
    }

    func testEmptyAndBrokenInputsFallBackSafely() {
        XCTAssertEqual(RHVoicePipelineSplitter.sentencePipelineFragments(from: ""), [""])
        // Truly malformed input (unterminated tag bracket) falls back to the original.
        XCTAssertEqual(
            RHVoicePipelineSplitter.sentencePipelineFragments(from: "Обірваний <pros"),
            ["Обірваний <pros"]
        )
        // An unclosed element whose brackets are closed is cleaned like everything else.
        XCTAssertEqual(
            RHVoicePipelineSplitter.sentencePipelineFragments(from: "<speak>Незакритий тег <prosody>текст."),
            ["<speak>Незакритий тег текст.</speak>"]
        )
    }
}
