import XCTest

final class RHVoiceTextBreaksTests: XCTestCase {
    // Живий замір VoiceOver, iPhone 17, iOS 27.0, 05.09.2026 (task-226): назва
    // елемента і слово ролі приходять як два окремих <s>, без коми між ними.
    private let capturedRoleWordSSML = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\">Файли GIF і наклейки</lang></s><s><lang xml:lang=\"uk-UA\">Кнопка</lang></s></prosody></speak>"

    func testPauseInsertedBeforeLastSentenceWhenItIsARoleWord() {
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: capturedRoleWordSSML)

        XCTAssertTrue(result.contains("<break strength='medium'/><s>"))

        guard let breakRange = result.range(of: "<break strength='medium'/>"),
              let firstSentenceRange = result.range(of: "Файли GIF і наклейки") else {
            return XCTFail("expected both the inserted break and the first sentence text to be present")
        }
        // Пауза стоїть перед ДРУГИМ <s> ("Кнопка"), а не перед першим.
        XCTAssertTrue(breakRange.lowerBound > firstSentenceRange.upperBound)
    }

    func testNoPauseWhenLastSentenceIsNotARoleWord() {
        let ssml = "<speak><s>Перше речення</s><s>Звичайне слово</s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertEqual(result, ssml)
        XCTAssertFalse(result.contains("<break"))
    }

    func testNoChangeWithFewerThanTwoSentences() {
        let ssml = "<speak><s><lang xml:lang=\"uk-UA\">Кнопка</lang></s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertEqual(result, ssml)
    }

    // task-226 round 2, ФАКТ/ВИСНОВОК: роль перевіряється лише щодо ОСТАННЬОГО
    // <s> у запиті. Три речення, роль — друге (не останнє) — паузи бути не
    // повинно, інакше ми паузимо будь-яке випадкове співпадіння тексту з
    // роллю всередині довгого тексту.
    func testNoPauseWhenRoleWordIsNotTheLastSentence() {
        let ssml = "<speak><s>Файли GIF і наклейки</s><s>Кнопка</s><s>Ще одне речення</s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertEqual(result, ssml)
        XCTAssertFalse(result.contains("<break"))
    }

    // Порожнє останнє речення не повинно ламати сканування тегів чи вставляти
    // паузу (порожній рядок ніколи не збігається зі словом ролі).
    func testNoChangeWhenLastSentenceIsEmpty() {
        let ssml = "<speak><s>Кнопка</s><s></s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertEqual(result, ssml)
        XCTAssertFalse(result.contains("<break"))
    }

    // task-226 round 7, п.5: a leading empty `<s></s>` must not count as a
    // sentence block either — otherwise "Кнопка" looks like the second of
    // two blocks (an empty one and itself) and gets a pause inserted before
    // it, even though there is really only ONE actual sentence here. That
    // pause tag would then have no text before it within its own pipeline
    // fragment (the empty sentence produces no fragment at all) — dead per
    // FACT 5.
    func testNoChangeWhenFirstSentenceIsEmpty() {
        let ssml = "<speak><s></s><s>Кнопка</s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertEqual(result, ssml, "only one non-empty sentence exists — there is nothing to pause before")
        XCTAssertFalse(result.contains("<break"))
    }

    // Список ролей має працювати не лише на «Кнопка»: перевіряємо друге слово
    // з таблиці trait.* і невидиму мітку U+200E, яку VoiceOver реально шле.
    // task-226 round 2: функція більше не приймає силу ззовні — завжди medium
    // (ФАКТ 2/3: weak і strong не дають робочої паузи, див. коментар над
    // insertPauseBeforeRoleWordSentence).
    func testPauseInsertedForAnotherRoleWordWithInvisibleMark() {
        let ssml = "<speak><s><lang xml:lang=\"uk-UA\">\u{200E}Налаштування</lang></s>"
            + "<s><lang xml:lang=\"uk-UA\">\u{200E}Заголовок</lang></s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertTrue(result.contains("<break strength='medium'/><s>"))
        guard let breakRange = result.range(of: "<break strength='medium'/>"),
              let firstSentenceRange = result.range(of: "Налаштування") else {
            return XCTFail("expected the break and the first sentence to be present")
        }
        XCTAssertTrue(breakRange.lowerBound > firstSentenceRange.upperBound)
    }

    // Роль може складатися з двох слів («Поле пошуку»): порівняння не повинно
    // ламатися на пробілі всередині.
    func testPauseInsertedForMultiWordRole() {
        let ssml = "<speak><s>Пошук</s><s>Поле пошуку</s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertTrue(result.contains("<break strength='medium'/><s>Поле пошуку</s>"))
    }

    // task-226 round 3, п.5: назва ролі приходить з крапкою на кінці ("Кнопка.")
    // — без обрізання пунктуації порівняння не спрацьовувало і пауза зникала.
    func testPauseInsertedWhenRoleWordHasTrailingPeriod() {
        let ssml = "<speak><s>Файли GIF і наклейки</s><s>Кнопка.</s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)

        XCTAssertTrue(result.contains("<break strength='medium'/><s>Кнопка.</s>"))
    }

    // task-226 round 3, п.7: роль не останнім реченням — паузи бути не
    // повинно (див. testNoPauseWhenRoleWordIsNotTheLastSentence), АЛЕ й
    // склейки слів через відкинуті <s> теги теж бути не повинно (п.1):
    // це саме речення потім іде до RHVoicePipelineSplitter.
    func testNoGluingWhenRoleWordIsNotTheLastSentence() {
        let ssml = "<speak><s>Файли GIF і наклейки</s><s>Кнопка</s><s>Ще одне речення</s></speak>"
        let result = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)
        XCTAssertEqual(result, ssml, "role word is not the last sentence — no pause inserted here")

        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: result)
        let joined = fragments.joined()
        XCTAssertFalse(joined.contains("наклейкиКнопка"))
        XCTAssertFalse(joined.contains("КнопкаЩе"))
    }

    // task-226 round 3, п.7: .none і wordGap=0 не повинні породжувати жодного
    // тега паузи взагалі (ранній guard у applyPunctuationAndWordGapBreaks).
    func testNoStrengthAndNoWordGapProducesNoBreakTags() {
        let input = "Привіт, світе. Як справи?"
        let result = RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(
            to: input,
            sentencePauseStrength: .none,
            wordGapMs: 0
        )

        XCTAssertFalse(result.contains("<break"))
        XCTAssertEqual(result, input)
    }

    func testPunctuationProducesStrengthBreakNotTime() {
        let result = RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(
            to: "Привіт, світе. Як справи?",
            sentencePauseStrength: .medium,
            wordGapMs: 0
        )

        XCTAssertTrue(result.contains("<break strength='medium'/>"))
        XCTAssertFalse(result.contains("time="))
    }

    // Сторожить крихку залежність, описану в задачі 226 round 2 п.5: пауза
    // перед словом ролі виживає лише тому, що
    // RHVoicePipelineSplitter.pipelineBodyByRemovingWrapperTags відкидає теги
    // <s> і <lang>, лишаючи <break/> недоторканим. Якщо спліттер колись
    // навчиться зберігати <s> на межі речень, ФАКТ 3 (document::add_break на
    // break_sentence НЕ створює паузу) означає, що ця пауза тихо зникне — цей
    // тест мусить впасти першим, коли таке станеться.
    // task-226 round 3, п.6: старий вхід (capturedRoleWordSSML) не містив
    // жодної крапки чи коми, тому розбивався на ОДИН фрагмент і не перевіряв
    // нічого небезпечного — вся ця перевірка проходила б і без фіксу п.1.
    // Новий вхід: довга назва елемента з крапкою в кінці, достатня, щоб
    // RHVoicePipelineSplitter реально розрізав текст на КІЛЬКА фрагментів, і
    // щоб слово ролі не приклеїлось до попереднього слова на межі розрізу.
    //
    // task-226 round 4, п.4: слово ролі тут навмисно ДОВГЕ ("Зображення",
    // 10 символів) — з коротким "Кнопка" (6 символів) старе, ще не
    // виправлене злиття `mergeSmallPipelineFragments` уже клеїло фрагмент з
    // паузою до сусіднього просто за правилом "менше 10 символів", і тест був
    // зелений навіть на старому коді, що ховав дефект п.3 (пауза для довгих
    // слів ролі мовчки зникала).
    private let longRoleWordSSML = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\">"
        + "Довге поле для перевірки розбиття тексту на кілька фрагментів у пайплайні синтезу мовлення."
        + "</lang></s><s><lang xml:lang=\"uk-UA\">Зображення</lang></s></prosody></speak>"

    // task-226 round 7: the break tag inserted before "Зображення" (10 real
    // characters — not under the 10-char merge threshold) lands right at the
    // natural sentence-fragment boundary, with no text before it WITHIN that
    // fragment (FACT 5). It is now deleted by `removeOrphanedBreakTags`
    // rather than rescued by merging fragments together, because that merge
    // (round 6) cascaded into collapsing an entire text into one fragment
    // whenever every sentence carries a trailing pause tag. No pause is
    // lost: `language::insert_pauses` (core/language.cpp:1827-1838) already
    // puts a silence segment at the start/end of every utterance sent to the
    // engine, so the fragment boundary itself is the pause. What must still
    // hold is that the role word survives intact as the whole content of its
    // own trailing fragment, not glued to anything before it.
    func testRoleWordPauseSurvivesPipelineSplitter() {
        let withPause = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: longRoleWordSSML)
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: withPause)

        XCTAssertGreaterThan(fragments.count, 1, "the long element name must force more than one fragment, otherwise this test proves nothing about splitting")

        let lastVisible = fragments.last!
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(lastVisible, "Зображення", "the role word must be the sole content of its own trailing fragment (the fragment boundary is the pause)")
        XCTAssertFalse(fragments.joined().contains("<break"), "the tag has no text before it in its own fragment (FACT 5) and must be deleted, not left dangling")
    }

    // task-226 round 5, головний тест заходу. `testRoleWordPauseSurvivesPipelineSplitter`
    // вище перевіряє "Зображення" БЕЗ крапки в кінці — а критик заміряв, що
    // саме роль З ВЛАСНОЮ крапкою (як реально приходить від VoiceOver) губила
    // паузу в 289 з 624 виміряних випадків, бо старий сторож
    // `mustMergeForBreakTag` дивився, чи закінчується НАСТУПНИЙ фрагмент
    // крапкою — а роль з крапкою під це під падає так само, як звичайне
    // речення, і склейку відміняв. Той самий вхід, що вище, але з крапкою
    // після "Зображення".
    private func longRoleWordSSMLWithTrailingPeriod(role: String) -> String {
        "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\">"
            + "Довге поле для перевірки розбиття тексту на кілька фрагментів у пайплайні синтезу мовлення."
            + "</lang></s><s><lang xml:lang=\"uk-UA\">\(role).</lang></s></prosody></speak>"
    }

    // task-226 round 7: same mechanism as `testRoleWordPauseSurvivesPipelineSplitter`
    // above — "Зображення." (11 real characters incl. the period, still not
    // under the 10-char merge threshold) lands the break tag at a fragment
    // boundary with nothing before it in that fragment (FACT 5), so it is
    // deleted; the fragment boundary itself is the pause.
    func testRoleWordWithTrailingPeriodPauseSurvivesPipelineSplitter() {
        let withPause = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: longRoleWordSSMLWithTrailingPeriod(role: "Зображення"))
        let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: withPause)

        XCTAssertGreaterThan(fragments.count, 1, "the long element name must force more than one fragment, otherwise this test proves nothing about splitting")

        let lastVisible = fragments.last!
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(lastVisible, "Зображення.", "the role word (with its own trailing period) must be the sole content of its own trailing fragment")
        XCTAssertFalse(fragments.joined().contains("<break"), "the tag has no text before it in its own fragment (FACT 5) and must be deleted, not left dangling")
    }

    // task-226 round 5, п.2 тестів: та сама перевірка для кількох слів ролі
    // різної довжини, щоб не лишити фікс прив'язаним лише до одного слова.
    //
    // task-226 round 7: whether the tag survives now depends on role-word
    // length. "Кнопка." (7 real chars) is under the 10-char small-fragment
    // merge threshold, so it still gets glued onto the preceding fragment —
    // WITH the break tag, which then has real text on both sides and
    // survives. "Зображення." (11) and "Панель інструментів." (20) are not
    // under that threshold, so the tag sits at a fragment boundary with
    // nothing before it in that fragment (FACT 5) and is deleted; the
    // fragment boundary itself gives the pause instead (see
    // `testRoleWordPauseSurvivesPipelineSplitter` above for the full
    // reasoning). Both outcomes are audibly a pause before the role word —
    // this test checks whichever one actually happened is internally
    // consistent, not that the tag always survives.
    func testMultipleRoleWordsWithTrailingPeriodPauseSurvivePipelineSplitter() {
        for role in ["Кнопка", "Зображення", "Панель інструментів"] {
            let withPause = RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: longRoleWordSSMLWithTrailingPeriod(role: role))
            let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: withPause)

            XCTAssertTrue(fragments.joined().contains("\(role)."), "role word '\(role).': the role word text must survive intact")

            if let fragmentWithBreak = fragments.first(where: { $0.contains("<break strength='medium'/>") }) {
                let breakRange = fragmentWithBreak.range(of: "<break strength='medium'/>")!
                let afterBreak = fragmentWithBreak[breakRange.upperBound...]
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertTrue(afterBreak.contains("\(role)."), "role word '\(role).': pause must have the role word in the SAME fragment, got tail '\(afterBreak)'")

                let beforeBreak = fragmentWithBreak[..<breakRange.lowerBound]
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertFalse(beforeBreak.isEmpty, "role word '\(role).': a surviving break with nothing before it in the same fragment does nothing either (FACT 5)")
            } else {
                XCTAssertGreaterThan(fragments.count, 1, "role word '\(role).': the tag was deleted as an orphan, so the pause must come from a fragment split instead")
                let lastVisible = fragments.last!
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertEqual(lastVisible, "\(role).", "role word '\(role).': expected it to be the sole content of its own trailing fragment")
            }
        }
    }

    // task-226 round 5, п.3 тестів: сторож проти повторення проблеми 2 —
    // «Проміжок між словами» не повинен розростити перший фрагмент. Той самий
    // текст, з увімкненим проміжком (50) і без нього (0), мусить дати
    // однакову кількість фрагментів і однакову довжину першого фрагмента:
    // критик заміряв на 3000 реальних текстах, що зі старим кодом середня
    // довжина першого фрагмента зростала з 25 до 256 символів.
    func testWordGapDoesNotChangeFragmentCountOrFirstFragmentLength() {
        // task-226 round 6: the previous string ("Один два три ...") did not
        // fail even on pre-fix code — it did not actually guard anything.
        // This one has no punctuation at all until the very end, so every
        // inter-word gap in the priority-first window gets a word-gap break.
        let words = "Привіт світе це довгий текст без жодного розділового знака аж до самого кінця речення."
        let baseline = RHVoicePipelineSplitter.pipelineFragments(from: "<speak>\(words)</speak>")
        let withWordGap = RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(
            to: "<speak>\(words)</speak>",
            sentencePauseStrength: .none,
            wordGapMs: 50
        )
        let withGap = RHVoicePipelineSplitter.pipelineFragments(from: withWordGap)

        // task-226 round 6, ФАКТ (замір на цьому вході): з увімкненим
        // проміжком тег стоїть ПЕРЕД буквально кожним міжслівним пробілом —
        // отже БУДЬ-ЯКИЙ кандидат на розріз у вікні 15…30 символів межує з
        // тегом з одного боку. Розрізати там означає або загубити паузу
        // (FACT 4, тег останній у fragments[0]), або зробити її нульовою
        // (FACT 5, тег перший у fragments[1]) — у цьому вхідному тексті БЕЗ
        // жодної коми немає "сусіднього безпечного пробілу", на який можна
        // зсунути кандидата. Єдиний варіант, що не порушує інваріант —
        // не різати тут (safety-net-злиття в mergeSmallPipelineFragments,
        // п.3, згортає fragments назад до одного шматка). Тому строга
        // рівність кількості/довжини фрагментів (як було в заході 5) більше
        // НЕ є досяжним інваріантом для цього конкретного входу — вона й не
        // мала бути, її "зелений" стан у попередніх заходах нічого не
        // сторожив (див. коментар до `words` вище). Що дійсно мусить
        // лишитись правдою — жоден тег паузи не осиротів.
        for fragment in withGap {
            assertBreakTagsAreNotOrphaned(in: fragment.ssml, scenario: "word gap enabled, fully packed text")
        }
        XCTAssertLessThanOrEqual(withGap.count, baseline.count, "word gap must never force MORE fragments than the plain text")
    }

    // task-226 round 7, тест 1 сторожа: критик заміряв, що вмикання паузи
    // «Звичайна» (без жодної зміни тексту) каскадно склеювало фрагменти —
    // КОЖНЕ речення закінчується тегом паузи, і старе правило
    // "merge fragment ending in a break tag into the next one" ланцюжком
    // зливало ввесь текст в один шматок (6 речень → 2 фрагменти, перший —
    // 178 символів замість 27). Кількість фрагментів і довжина першого
    // фрагмента з увімкненою паузою мусять збігатися з тими самими без неї —
    // осиротілий тег тепер видаляється (`removeOrphanedBreakTags`), а не
    // рятується злиттям.
    func testSentencePauseDoesNotChangeFragmentCountOrFirstFragmentLength() {
        let sentences = (1...6).map { "Це речення номер \($0) містить достатньо слів для перевірки." }
        let text = "<speak>\(sentences.joined(separator: " "))</speak>"

        let baseline = RHVoicePipelineSplitter.pipelineFragments(
            from: RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(to: text, sentencePauseStrength: .none, wordGapMs: 0)
        )
        let withPause = RHVoicePipelineSplitter.pipelineFragments(
            from: RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(to: text, sentencePauseStrength: .medium, wordGapMs: 0)
        )

        XCTAssertEqual(withPause.count, baseline.count, "enabling the sentence pause must not change how many fragments the pipeline produces")
        XCTAssertEqual(
            RHVoicePipelineSplitter.textCharacterCount(in: withPause[0].ssml),
            RHVoicePipelineSplitter.textCharacterCount(in: baseline[0].ssml),
            "enabling the sentence pause must not change the length of the first fragment"
        )
    }

    // task-226 round 7, тест 2 сторожа: критик заміряв, що вмикання
    // проміжку 50 (текст без жодного розділового знака) відкидало
    // ПРІОРИТЕТНИЙ перший розріз узагалі — тег стоїть перед кожним
    // міжслівним пробілом, і стара відбраковка кандидата (`isSplitCandidateAdjacentToBreakTag`)
    // відхиляла їх усі. Прибравши відбраковку (розріз обирається як раніше)
    // і чистячи осиротілі теги вже ПІСЛЯ нарізки, довжина/кількість
    // фрагментів з проміжком 50 і без нього (0) мусять збігатися.
    func testWordGapProducesSameFragmentCountAndFirstFragmentLengthAsNoGap() {
        let words = "Привіт світе це довгий текст без жодного розділового знака аж до самого кінця"
        let text = "<speak>\(words)</speak>"

        let baseline = RHVoicePipelineSplitter.pipelineFragments(
            from: RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(to: text, sentencePauseStrength: .none, wordGapMs: 0)
        )
        let withGap = RHVoicePipelineSplitter.pipelineFragments(
            from: RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(to: text, sentencePauseStrength: .none, wordGapMs: 50)
        )

        XCTAssertEqual(withGap.count, baseline.count, "enabling the word gap must not change how many fragments the pipeline produces")
        XCTAssertEqual(
            RHVoicePipelineSplitter.textCharacterCount(in: withGap[0].ssml),
            RHVoicePipelineSplitter.textCharacterCount(in: baseline[0].ssml),
            "enabling the word gap must not change the length of the first fragment"
        )
    }

    // task-226 round 6, головний інваріант заходу: жоден фрагмент, що йде до
    // движка, не повинен мати тег <break .../> ані першим, ані останнім
    // вмістом — з обох боків мусить бути непорожній текст У ТОМУ Ж фрагменті.
    // FACT 4 (core/language.cpp:1437-1442): немає тексту ПІСЛЯ тега в цьому ж
    // фрагменті — команда паузи мовчки губиться.
    // FACT 5 (core/document.hpp:235-243): немає тексту ПЕРЕД тегом у цьому ж
    // фрагменті — команда паузи взагалі не виконується (TokStructure ще не
    // створено, вона ліниво створюється першим текстовим токеном).
    func testBreakTagNeverOrphanedAcrossDiverseInputs() {
        var scenarios: [(label: String, fragments: [String])] = []

        scenarios.append((
            "жива фіксація VoiceOver",
            RHVoicePipelineSplitter.sentencePipelineFragments(
                from: RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: capturedRoleWordSSML)
            )
        ))

        scenarios.append((
            "довга назва з крапкою + слово ролі з власною крапкою",
            RHVoicePipelineSplitter.sentencePipelineFragments(
                from: RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(
                    in: longRoleWordSSMLWithTrailingPeriod(role: "Зображення")
                )
            )
        ))

        // Довжина назви елемента навмисно ≈25 символів — саме те вікно
        // (15…30), де `priorityFirstFragmentSplitIndex` шукає кандидата на
        // розріз, і саме цей розмір критик заміряв як проблемний для 56
        // випадків у четвертому/п'ятому заходах.
        let titleAboutTwentyFiveChars = "Кнопка для швидкого старту"
        for role in RHVoiceTextBreaks.roleWordsRequiringPauseBeforeLastSentence {
            let ssml = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\">"
                + titleAboutTwentyFiveChars
                + "</lang></s><s><lang xml:lang=\"uk-UA\">\(role)</lang></s></prosody></speak>"
            scenarios.append((
                "слово ролі '\(role)', назва ≈25 символів",
                RHVoicePipelineSplitter.sentencePipelineFragments(
                    from: RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: ssml)
                )
            ))
        }

        let wordGapText = "Привіт світе це довгий текст без жодного розділового знака аж до самого кінця речення."
        scenarios.append((
            "текст з увімкненим проміжком між словами",
            RHVoicePipelineSplitter.sentencePipelineFragments(
                from: RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(
                    to: "<speak>\(wordGapText)</speak>",
                    sentencePauseStrength: .none,
                    wordGapMs: 50
                )
            )
        ))

        // task-226 round 7: шість речень з увімкненою паузою «Звичайна» —
        // саме той вхід, де старе правило злиття "фрагмент, що кінчається
        // тегом паузи" каскадно зливало все в один шматок.
        let sixSentences = (1...6).map { "Це речення номер \($0) містить достатньо слів для перевірки." }
        scenarios.append((
            "шість речень з паузою «Звичайна»",
            RHVoicePipelineSplitter.sentencePipelineFragments(
                from: RHVoiceTextBreaks.applyPunctuationAndWordGapBreaks(
                    to: "<speak>\(sixSentences.joined(separator: " "))</speak>",
                    sentencePauseStrength: .medium,
                    wordGapMs: 0
                )
            )
        ))

        // task-226 round 7, п.5: порожнє перше речення не повинно
        // рахуватись як окремий блок — інакше фрагмент, що йде до движка,
        // починається з тега паузи без тексту перед ним у тому ж фрагменті.
        scenarios.append((
            "порожнє перше речення",
            RHVoicePipelineSplitter.sentencePipelineFragments(
                from: RHVoiceTextBreaks.insertPauseBeforeRoleWordSentence(in: "<speak><s></s><s>Кнопка</s></speak>")
            )
        ))

        for scenario in scenarios {
            for fragment in scenario.fragments {
                assertBreakTagsAreNotOrphaned(in: fragment, scenario: scenario.label)
            }
        }
    }

    private func assertBreakTagsAreNotOrphaned(in fragment: String, scenario: String, file: StaticString = #filePath, line: UInt = #line) {
        var searchRange = fragment.startIndex..<fragment.endIndex
        while let tagRange = fragment.range(
            of: #"<break\b[^>]*/>"#,
            options: [.regularExpression, .caseInsensitive],
            range: searchRange
        ) {
            let before = String(fragment[..<tagRange.lowerBound])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(fragment[tagRange.upperBound...])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            XCTAssertFalse(before.isEmpty, "[\(scenario)] break tag has no text before it in the same fragment: '\(fragment)'", file: file, line: line)
            XCTAssertFalse(after.isEmpty, "[\(scenario)] break tag has no text after it in the same fragment: '\(fragment)'", file: file, line: line)

            searchRange = tagRange.upperBound..<fragment.endIndex
        }
    }
}
