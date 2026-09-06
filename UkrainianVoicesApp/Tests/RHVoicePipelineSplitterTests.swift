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

    // task-226 round 6: a break tag right at a sentence boundary ("Перше
    // речення.<break/> Друге речення.") has no text after it in fragment 1
    // within that fragment — merging the two sentences into one fragment was
    // round 6's fix (FACT 4/5), but merging on "ends with a break tag"
    // cascades: with the sentence pause enabled every sentence ends in a
    // break tag, so the whole text collapsed into one fragment (task-226
    // round 7 critic measurement). Round 7 replaces the merge with deleting
    // the orphaned tag instead — the fragment boundary itself still gives a
    // pause (`language::insert_pauses`, core/language.cpp:1827-1838, puts
    // silence at the start/end of every utterance) — so this is back to 2
    // separate fragments, this time with the dead tag removed rather than
    // dangling.
    func testBreakTagsStayInsideFragments() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak>Перше речення.<break time=\"250ms\"/> Друге речення.</speak>"
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments[0].contains("Перше речення."))
        XCTAssertTrue(fragments[1].contains("Друге речення."))
        XCTAssertFalse(fragments.joined().contains("<break"), "the tag has no text after it within fragment 1 (FACT 4) and must be deleted, not left dangling")
        XCTAssertFalse(fragments.joined().contains("  "), "no double spaces should appear where the orphaned tag was removed")
    }

    func testLongTextWithManySentencesSplits() {
        let sentences = (1...6).map { "Це довге тестове речення номер \($0), яке має достатньо слів для перевірки." }
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: "<speak>\(sentences.joined(separator: " "))</speak>")

        XCTAssertGreaterThanOrEqual(fragments.count, 6)
        XCTAssertLessThan(RHVoicePipelineSplitter.textCharacterCount(in: fragments[0]), 80)
    }

    func testPriorityFirstRemainderContinuesSentence() {
        let fragments = RHVoicePipelineSplitter.pipelineFragments(
            from: "<speak>Це довге повідомлення для перевірки швидкого старту, воно має продовження без завершення речення. Друге речення починається окремо.</speak>"
        )

        XCTAssertGreaterThanOrEqual(fragments.count, 3)
        XCTAssertFalse(fragments[0].continuesSentence)
        XCTAssertTrue(fragments[1].continuesSentence)
        XCTAssertFalse(fragments.last!.continuesSentence)
    }

    func testSentenceFragmentsDoNotContinueSentence() {
        let fragments = RHVoicePipelineSplitter.pipelineFragments(
            from: "<speak>Перше речення має достатньо слів. Друге речення теж звучить окремо.</speak>"
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments.allSatisfy { !$0.continuesSentence })
    }

    func testDecimalNumbersAreNotSentenceBoundaries() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak>Версія 3.14 працює стабільно. Наступне речення звучить окремо.</speak>"
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertTrue(fragments[0].contains("3.14"))
        XCTAssertEqual(RHVoicePipelineSplitter.textCharacterCount(in: fragments[0]), "Версія 3.14 працює стабільно.".count)
    }

    // task-226 round 3, головний тест заходу. ФАКТ A: pipelineBodyByRemovingWrapperTags
    // відкидав теги <s>/<lang>, лишаючи на їх місці НІЧОГО — сусідні текстові
    // вузли зливались в одне слово. ФАКТ B (core/document.hpp:518-533): двигун
    // ріже текст на токени лише по пробілах, тож "наклейкиКнопка" — одне слово,
    // одне наголошення. Вхід тут — реальна форма VoiceOver capture (без пробілу
    // між сусідніми <s>), яку жодна кома чи крапка не рятує.
    func testAdjacentSentenceTagsWithoutSpaceDoNotGlueWords() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak><s><lang xml:lang=\"uk-UA\">наклейки</lang></s><s><lang xml:lang=\"uk-UA\">Кнопка</lang></s></speak>"
        )

        XCTAssertEqual(fragments.count, 1)
        XCTAssertFalse(fragments[0].contains("наклейкиКнопка"), "dropping <s>/<lang> between two text nodes must not glue them into one word/token")
        XCTAssertTrue(fragments[0].contains("наклейки Кнопка"), "exactly one separating space must appear where the tags were dropped")
    }

    // Той самий сценарій, але роль не остання (три речення) — паузи Андрій не
    // просив, але склейка тегом-відкиданням лишається реальним ризиком
    // незалежно від того, чи є слово роллю зі списку.
    func testAdjacentSentenceTagsWithoutSpaceDoNotGlueWordsAcrossThreeSentences() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak><s>Файли GIF і наклейки</s><s>Кнопка</s><s>Ще одне речення</s></speak>"
        )

        let joined = fragments.joined()
        XCTAssertFalse(joined.contains("наклейкиКнопка"))
        XCTAssertFalse(joined.contains("КнопкаЩе"))
    }

    // Тег паузи (<break/>) — не звичайний тег, він лишається як є (не
    // замінюється пробілом): переконуємось, що ця гілка досі не зачеплена, і
    // що сусідні відкинуті теги не наплодили подвійних пробілів навколо нього.
    func testBreakTagIsNotReplacedBySpace() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "<speak><s>Перше</s><break strength=\"medium\"/><s>Друге</s></speak>"
        )

        let joined = fragments.joined()
        XCTAssertTrue(joined.contains("<break strength=\"medium\"/>"), "the break tag itself must survive verbatim, not be replaced by a space")
        XCTAssertFalse(joined.contains("  "), "no double spaces should appear around a preserved tag")
    }

    // task-226 round 4, п.1: `RHVoiceApostropheNormalizer` wraps every
    // two-plus-letter Latin abbreviation in `<say-as interpret-as="characters">`
    // on EVERY request. The splitter drops that tag when building the pipeline
    // body — before this fix it inserted a marker (later resolved to a space)
    // for ANY dropped tag, not just sentence/paragraph boundaries, so ordinary
    // screen text like "PDF-файл" came out as "PDF -файл".
    // Dictionary disabled here on purpose: "PDF" is ALSO a bundled abbreviation
    // dictionary entry (spelled out before normalizeLatinAbbreviations even
    // runs), which would make this test pass for the wrong reason (no <say-as>
    // ever produced) regardless of the splitter fix under test.
    func testLatinAbbreviationSayAsDoesNotInsertSpaceInsideHyphenatedWord() {
        let normalized = RHVoiceApostropheNormalizer.normalizeInTextSegments("Це PDF-файл.", abbreviationDictionaryEnabled: false)
        XCTAssertTrue(normalized.contains("<say-as"), "test assumes normalizeInTextSegments actually wraps PDF in <say-as> — otherwise this test proves nothing")

        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: "<speak>\(normalized)</speak>")
        let joined = fragments.joined()
        XCTAssertFalse(joined.contains("PDF -"), "dropping <say-as> around a Latin abbreviation must not insert a space before the following hyphen")
    }

    // task-226 round 4, п.1 (same failure, opening quote): the dropped
    // <say-as> tag also sat right after "«" — a marker there produced
    // "« VPN»" instead of "«VPN»". Dictionary disabled for the same reason as
    // above ("VPN" is also a bundled dictionary entry).
    func testLatinAbbreviationSayAsDoesNotInsertSpaceAfterOpeningQuote() {
        let normalized = RHVoiceApostropheNormalizer.normalizeInTextSegments("«VPN» увімкнено", abbreviationDictionaryEnabled: false)
        XCTAssertTrue(normalized.contains("<say-as"), "test assumes normalizeInTextSegments actually wraps VPN in <say-as> — otherwise this test proves nothing")

        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: "<speak>\(normalized)</speak>")
        let joined = fragments.joined()
        XCTAssertFalse(joined.contains("« VPN"), "dropping <say-as> right after an opening quote must not insert a space")
    }

    // task-226 round 4, п.2: `mergeSmallPipelineFragments` used to glue a short
    // trailing fragment onto the previous one with plain `+=`, with no
    // separator — reproduced here with NO tags at all, so this only exercises
    // the merge step, not the dropped-tag marker from п.1.
    func testMergingSmallFragmentsDoesNotGlueWords() {
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(
            from: "добре так файл телефон нове кнопка. мама світ екран."
        )
        let joined = fragments.joined()
        XCTAssertFalse(joined.contains("новекнопка"), "merging a short fragment into the previous one must not glue the last word of one onto the first word of the next")
    }

    // task-226 round 8. FACT 6 (`core/language.cpp:1827-1838`) says the seam
    // between two fragments keeps its pause even after the orphaned break
    // tag is deleted, because `insert_pauses` puts silence at the start/end
    // of every engine utterance regardless of tags. But
    // `RHVoiceSilenceAnalyzer.trimMidSentenceSilence` (called from
    // `UkrainianSpeechSynthesizer` with `trimLeading: fragment.continuesSentence`
    // and `trimTrailing: nextFragment.continuesSentence`) trims up to 250ms off
    // BOTH sides of a seam whose right-hand fragment still claims
    // `continuesSentence == true` — which used to happen even after the tag
    // that "caused" the seam was deleted, erasing the very pause FACT 6 kept.
    // The fix: when cleanup deletes an orphaned tag at a fragment edge, the
    // fragment on the right of that seam must stop claiming
    // `continuesSentence`.
    private func roleWordFragments(elementText: String, role: String) -> [RHVoicePipelineSplitter.PipelineFragment] {
        let ssml = "<speak><s><lang xml:lang=\"uk-UA\">\(elementText)</lang></s><s><lang xml:lang=\"uk-UA\">\(role)</lang></s></speak>"
        let withPause = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)
        return RHVoicePipelineSplitter.pipelineFragments(from: withPause)
    }

    func testOrphanedPauseTagRemovalClearsContinuesSentenceOnRoleFragment() {
        // "Зображення" — рівно 10 символів, межа мерджу коротких фрагментів
        // (`mergeSmallPipelineFragments` зливає лише те, що <10).
        let fragments = roleWordFragments(elementText: "Файли GIF і наклейки", role: "Зображення")

        guard let roleFragment = fragments.last(where: { $0.ssml.contains("Зображення") }) else {
            return XCTFail("expected a fragment containing the role word")
        }
        XCTAssertFalse(roleFragment.continuesSentence, "the seam that lost its pause tag must not be trimmed by RHVoiceSilenceAnalyzer")
    }

    // Кілька довжин назви елемента (19–30 символів) і кілька ролей зі списку
    // `RHVoiceTextBreaks.roleWordsRequiringPauseBeforeLastSentence` — заміри
    // критика (564 з 14880) показали дефект саме в цьому діапазоні довжин.
    func testOrphanedPauseTagRemovalClearsContinuesSentenceAcrossElementLengthsAndRoles() {
        let cases: [(elementText: String, role: String)] = [
            ("Налаштування конфіденційності", "Зображення"),
            ("Історія переглядів сторінок", "Зображення"),
            ("Кнопка для швидкого старту", "Зображення"),
            ("Показати більше деталей тут", "Заголовок"),
            ("Перейти на головну сторінку", "Посилання"),
            ("Швидкі дії для документа тут", "Панель інструментів")
        ]

        for testCase in cases {
            let fragments = roleWordFragments(elementText: testCase.elementText, role: testCase.role)
            guard let roleFragment = fragments.last(where: { $0.ssml.contains(testCase.role) }) else {
                XCTFail("expected a fragment containing role word '\(testCase.role)' for element '\(testCase.elementText)'")
                continue
            }
            XCTAssertFalse(
                roleFragment.continuesSentence,
                "role '\(testCase.role)' after '\(testCase.elementText)' (\(testCase.elementText.count) chars) must not continue the sentence once the seam's pause tag was orphaned away"
            )
        }
    }

    // Розріз посеред фрази (жодного break-тегу немає, отже нема чого
    // видаляти на шві) не повинен втратити свою злитність — інакше постраждає
    // мова там, де розріз пройшов не по паузі ролі.
    func testMidSentenceSplitWithoutOrphanedTagKeepsContinuesSentence() {
        let fragments = RHVoicePipelineSplitter.pipelineFragments(
            from: "<speak>Це дуже довге речення, яке обов'язково перевищує вісімдесят символів і тому має бути розбите на частини за комою для перевірки поведінки розбивача.</speak>"
        )

        XCTAssertGreaterThan(fragments.count, 1)
        XCTAssertTrue(fragments.dropFirst().contains { $0.continuesSentence }, "a mid-sentence continuation fragment should still claim continuesSentence when no pause tag was removed at its seam")
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
