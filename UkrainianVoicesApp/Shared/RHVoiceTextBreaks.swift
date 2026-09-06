import Foundation

/// Inserts `<break>` elements into an already-built SSML request before it
/// reaches the RHVoice engine. Two independent passes:
/// - punctuation/word-gap breaks (`applyPunctuationAndWordGapBreaks`), driven
///   by the "Пауза після розділових знаків" and "Проміжок між словами" voice
///   settings;
/// - a pause before a final `<s>` sentence that is itself a VoiceOver role
///   word (`insertPauseBeforeRoleWordSentence`), because VoiceOver sends the
///   element name and its role as two separate `<s>` with no punctuation
///   between them. Unconditional — NOT tied to the punctuation-pause
///   setting above, see the function's doc comment for why.
enum RHVoiceTextBreaks {
    // MARK: - Punctuation and word-gap breaks

    static func applyPunctuationAndWordGapBreaks(to ssml: String, sentencePauseStrength: RHVoicePauseStrength, wordGapMs: Int) -> String {
        let sentenceBreakTag = sentencePauseStrength.ssmlValue.map { "<break strength='\($0)'/>" }
        guard sentenceBreakTag != nil || wordGapMs > 0 else { return ssml }

        var output = ""
        var textSegment = ""
        var tagSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tagSegment.append(character)
                if character == ">" {
                    output += transformTextSegment(textSegment, sentenceBreakTag: sentenceBreakTag, wordGapMs: wordGapMs)
                    textSegment.removeAll(keepingCapacity: true)
                    output += tagSegment
                    tagSegment.removeAll(keepingCapacity: true)
                    insideTag = false
                }
            } else if character == "<" {
                insideTag = true
                tagSegment.append(character)
            } else {
                textSegment.append(character)
            }
        }

        if insideTag {
            output += textSegment + tagSegment
        } else {
            output += transformTextSegment(textSegment, sentenceBreakTag: sentenceBreakTag, wordGapMs: wordGapMs)
        }

        if output.range(of: #"<\s*speak\b"#, options: .regularExpression) != nil {
            return output
        }
        return "<speak>\(output)</speak>"
    }

    private static func transformTextSegment(_ text: String, sentenceBreakTag: String?, wordGapMs: Int) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        var output = ""
        for index in characters.indices {
            let character = characters[index]
            output.append(character)

            if let sentenceBreakTag, isSentencePunctuation(character), !isDecimalSeparator(characters, at: index) {
                output += sentenceBreakTag
            }

            if wordGapMs > 0 && isWordCharacter(character) {
                let nextIndex = index + 1
                if nextIndex < characters.count, isWhitespace(characters[nextIndex]), nextWordStarts(afterWhitespaceFrom: nextIndex, in: characters) {
                    output += "<break time='\(wordGapMs)ms'/>"
                }
            }
        }
        return output
    }

    private static func nextWordStarts(afterWhitespaceFrom index: Int, in characters: [Character]) -> Bool {
        var cursor = index
        while cursor < characters.count, isWhitespace(characters[cursor]) {
            cursor += 1
        }
        return cursor < characters.count && isWordCharacter(characters[cursor])
    }

    private static func isSentencePunctuation(_ character: Character) -> Bool {
        character == "." || character == "," || character == "!" || character == "?"
    }

    private static func isDecimalSeparator(_ characters: [Character], at index: Int) -> Bool {
        guard characters[index] == "." || characters[index] == "," else { return false }
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        return previous?.isNumber == true && next?.isNumber == true
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    // MARK: - Role-word pause before the last sentence

    /// Sentences whose full text (after stripping nested tags, invisible
    /// characters and surrounding whitespace) means "this is a VoiceOver role
    /// spoken as its own `<s>` right after the element name — insert the
    /// sentence pause before it too". INCOMPLETE by design: only words
    /// actually measured on Андрій's device belong here. Extend as new
    /// measurements come in (added "Кнопка" 2026-09-05, iPhone 17, iOS 27.0).
    ///
    /// Джерело формулювань (прочитано на Маку 2026-09-05, звірено вручну):
    /// iOS 26.5 simulator runtime →
    /// `System/Library/AccessibilityBundles/UIKit.axbundle/uk.lproj/Accessibility.strings`,
    /// ключі `trait.*`. Сюди внесені ЛИШЕ слова-ТИПИ елемента. Слова-стани з тієї
    /// самої таблиці (Вибрано, Не увімкнено, Регульований, Відтворює звук …) свідомо
    /// НЕ внесені: скарга Андрія саме про злиття «назва + тип», а не про стан.
    /// «Вкладка», «Прапорець», «Текстове поле» НЕ вгадуються: суцільний перегляд
    /// усіх axbundle цього runtime не знайшов їх як загальносистемні слова.
    ///
    /// `RHVoicePipelineSplitter` (task-226 round 5) не ставить межу фрагмента
    /// одразу після `<break .../>` незалежно від довжини слова ролі чи його
    /// власної крапки — тег лишається на початку фрагмента разом із
    /// наступним словом, а не в хвості попереднього, де ФАКТ 4
    /// (`core/language.cpp:1437-1442`, phrasify) мовчки губить паузу без
    /// наступного слова В МЕЖАХ ТОГО Ж фрагмента.
    static let roleWordsRequiringPauseBeforeLastSentence: [String] = [
        "Кнопка",              // trait.button — ЗАМІРЯНО на пристрої 05.09.2026
        "Заголовок",           // trait.header
        "Зображення",          // trait.image
        "Клавіша",             // trait.keyboardkey
        "Посилання",           // trait.link
        "Поле пошуку",         // trait.searchfield
        "Статичний текст",     // trait.statictext
        "Табуляція",           // trait.tab
        "Перемкнути",          // trait.toggle
        "Спливна кнопка",      // popup.button
        "Смуга вкладок",       // tab.bar.label
        "Панель інструментів"  // toolbar.label
    ]

    /// Inserts a `<break>` right before the opening `<s>` tag of the LAST
    /// sentence, but only when that sentence is exactly one of
    /// `roleWordsRequiringPauseBeforeLastSentence` and there are at least two
    /// `<s>` sentences in `ssml`. Deliberately narrow: a blanket pause between
    /// every sentence was rejected (it chops up ordinary long text).
    ///
    /// Always emits `strength='medium'`, unconditionally — NOT the user's
    /// punctuation-pause setting. This is not configurable because it is not
    /// a choice: `weak` resolves to `break_default`, which
    /// `language::get_word_break` discards in favour of the phrasing tree,
    /// i.e. no pause at all (FACT 2, `core/language.cpp:1399-1415`) — no good
    /// as a fix for a silent seam. `strong` calls `document::add_break`'s
    /// `break_sentence` branch (`core/document.hpp:434-438`), which does NOT
    /// itself emit a pause command, but DOES end the sentence early, and
    /// `language::insert_pauses` (`core/language.cpp:1827-1838`) puts a `pau`
    /// segment at the start and end of every sentence — so `strong` would
    /// still produce an audible pause here (task-226 round 3 correction of an
    /// earlier, wrong "no pause at all" claim). It is left unused in THIS
    /// function anyway: forcing an early sentence end changes phrasing/prosody
    /// for the fragment split downstream (`RHVoicePipelineSplitter`) in ways
    /// nobody has measured on-device, while `medium` (`break_phrase`) gives an
    /// audible pause with no such side effect.
    static func insertPauseBeforeRoleWordSentence(in ssml: String) -> String {
        let characters = Array(ssml)
        let blocks = sentenceBlocks(in: characters)
        guard blocks.count >= 2, let last = blocks.last else { return ssml }

        let content = String(characters[last.contentRange])
        guard isRoleWordSentence(content) else { return ssml }

        let breakTag = "<break strength='medium'/>"
        var output = String(characters[0..<last.openTagStart])
        output += breakTag
        output += String(characters[last.openTagStart...])
        return output
    }

    private struct SentenceBlock {
        let openTagStart: Int
        let contentRange: Range<Int>
    }

    /// Finds top-level `<s>...</s>` blocks by scanning tags left to right.
    /// Sentences are assumed not to nest inside each other (VoiceOver/AVSpeech
    /// SSML never does), so a single pending-open slot is enough.
    private static func sentenceBlocks(in characters: [Character]) -> [SentenceBlock] {
        var blocks: [SentenceBlock] = []
        var pendingOpenStart: Int?
        var pendingContentStart: Int?
        var index = 0

        while index < characters.count {
            guard characters[index] == "<" else {
                index += 1
                continue
            }
            var tagEnd = index + 1
            while tagEnd < characters.count, characters[tagEnd] != ">" {
                tagEnd += 1
            }
            guard tagEnd < characters.count else { break }
            let tagBody = String(characters[(index + 1)..<tagEnd])

            if isClosingSentenceTag(tagBody) {
                if let openStart = pendingOpenStart, let contentStart = pendingContentStart,
                   characters[contentStart..<index].contains(where: { !isWhitespace($0) }) {
                    blocks.append(SentenceBlock(openTagStart: openStart, contentRange: contentStart..<index))
                }
                pendingOpenStart = nil
                pendingContentStart = nil
            } else if isOpeningSentenceTag(tagBody), pendingOpenStart == nil {
                pendingOpenStart = index
                pendingContentStart = tagEnd + 1
            }
            index = tagEnd + 1
        }
        return blocks
    }

    private static func isOpeningSentenceTag(_ tagBody: String) -> Bool {
        tagBody == "s" || tagBody.hasPrefix("s ") || tagBody.hasPrefix("s\t")
    }

    private static func isClosingSentenceTag(_ tagBody: String) -> Bool {
        tagBody == "/s"
    }

    private static func isRoleWordSentence(_ rawContent: String) -> Bool {
        let normalized = normalizedRoleComparisonText(rawContent)
        guard !normalized.isEmpty else { return false }
        return roleWordsRequiringPauseBeforeLastSentence.contains {
            normalizedRoleComparisonText($0) == normalized
        }
    }

    /// Strips nested tags (e.g. `<lang>`), invisible formatting characters
    /// (e.g. U+200E LRM — seen in a live VoiceOver capture), surrounding
    /// whitespace and punctuation, and case, so the comparison survives what
    /// VoiceOver actually sends rather than an idealized string. Trailing
    /// punctuation matters in practice: a role word landing as the last `<s>`
    /// can pick up a sentence-final period from upstream text assembly (e.g.
    /// "Кнопка."), and without stripping it here that period alone made the
    /// comparison miss an otherwise-exact role word (task-226 round 3).
    private static func normalizedRoleComparisonText(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let visibleScalars = withoutTags.unicodeScalars.filter { !invisibleFormattingScalars.contains($0) }
        let visible = String(String.UnicodeScalarView(visibleScalars))
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return visible.trimmingCharacters(in: trimSet).lowercased()
    }

    private static let invisibleFormattingScalars: Set<UnicodeScalar> = {
        var scalars = Set<UnicodeScalar>()
        for value: UInt32 in 0x200B...0x200F {
            scalars.insert(UnicodeScalar(value)!)
        }
        scalars.insert(UnicodeScalar(0x2060)!) // word joiner
        scalars.insert(UnicodeScalar(0xFEFF)!) // BOM / zero-width no-break space
        return scalars
    }()
}
