import Foundation
import os.log

enum RHVoicePipelineSplitter {
    private static let diagnosticLog = OSLog(subsystem: "com.rhvoice.UkrainianVoices", category: "latency")

    struct PipelineFragment {
        let ssml: String
        let continuesSentence: Bool
    }

    static func sentencePipelineFragments(from ssml: String) -> [String] {
        pipelineFragments(from: ssml).map(\.ssml)
    }

    static func pipelineFragments(from ssml: String) -> [PipelineFragment] {
        logSSMLTagNames(from: ssml)

        guard let strippedBody = pipelineBodyByRemovingWrapperTags(from: ssml) else {
            logPipelinePlan(fragmentCount: 1, totalLength: ssml.count)
            return [PipelineFragment(ssml: ssml, continuesSentence: false)]
        }
        // Single-fragment fallbacks must also go through the cleaned body: returning
        // the original ssml (with unknown tags) would send short texts down the
        // engine's plain-text fallback with a different rate formula than split
        // fragments use — short and long texts must sound identical.
        let cleanedWholeUtterance: [PipelineFragment] = {
            let trimmed = strippedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = trimmed.isEmpty ? ssml : "<speak>\(strippedBody)</speak>"
            return [PipelineFragment(ssml: fallback, continuesSentence: false)]
        }()
        let bodyFragments = splitPipelineBodyIntoSentenceFragments(strippedBody)
        let pipelineFragments = bodyFragments.flatMap { splitLongPipelineFragment($0) }
        let priorityFragments = splitPriorityFirstFragment(pipelineFragments)
        guard priorityFragments.count > 1 else {
            logPipelinePlan(fragmentCount: 1, totalLength: ssml.count)
            return cleanedWholeUtterance
        }

        let breakCleanups = mergeSmallPipelineFragments(priorityFragments)
            .map { fragment -> (body: FragmentBody, cleanup: OrphanBreakCleanup) in
                let cleanup = removeOrphanedBreakTags(from: fragment.text)
                return (FragmentBody(text: cleanup.text, continuesSentence: fragment.continuesSentence), cleanup)
            }
        var mergedFragments = breakCleanups.map(\.body)
        // The break tag we just deleted was the ONLY thing telling
        // trimLeading/trimTrailing (UkrainianSpeechSynthesizer) this seam
        // needed a pause: `insert_pauses` still puts silence here (that's WHY
        // deleting a dead tag loses no pause, see the comment above), but our
        // OWN `RHVoiceSilenceAnalyzer.trimMidSentenceSilence` trims up to
        // 250ms off BOTH sides of a `continuesSentence` seam — so without
        // this, the tag's removal and the trimmer's default combine to erase
        // the very pause FACT 6 said the seam would keep (task-226 round 8,
        // measured on real captions: "Файли GIF і наклейки" + "Зображення").
        // Only the fragment(s) that actually lost a tag at their edge are
        // touched — a seam with no orphaned tag keeps its `continuesSentence`
        // as-is, so ordinary mid-sentence splits stay glued together.
        for index in breakCleanups.indices {
            if breakCleanups[index].cleanup.removedLeadingOrphan {
                mergedFragments[index].continuesSentence = false
            }
            if breakCleanups[index].cleanup.removedTrailingOrphan, index + 1 < mergedFragments.count {
                mergedFragments[index + 1].continuesSentence = false
            }
        }
        guard mergedFragments.count > 1,
              mergedFragments.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            logPipelinePlan(fragmentCount: 1, totalLength: ssml.count)
            return cleanedWholeUtterance
        }

        let fragments = mergedFragments.map {
            PipelineFragment(ssml: "<speak>\($0.text)</speak>", continuesSentence: $0.continuesSentence)
        }
        logPipelinePlan(fragmentCount: fragments.count, totalLength: ssml.count)
        return fragments
    }

    static func textCharacterCount(in ssml: String) -> Int {
        extractTextSegments(from: ssml)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count
    }

    // Sentinel for "a non-break tag was dropped here" — resolved into a real
    // space (or nothing) by `resolvingDroppedTagMarkers` once the full text on
    // both sides of the drop is known. Control character, cannot appear in
    // VoiceOver/app-supplied text.
    private static let droppedTagMarker: Character = "\u{1}"

    private static func pipelineBodyByRemovingWrapperTags(from ssml: String) -> String? {
        var output = ""
        var tag = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tag.append(character)
                if character == ">" {
                    if isPipelineBreakTag(tag) {
                        output += tag
                    } else if isSentenceOrParagraphBoundaryTag(tag) {
                        // speak/prosody wrappers and unknown (VoiceOver service) tags
                        // are dropped, keeping their inner text: the engine rejects
                        // unknown tags, which triggered the per-fragment plain-text
                        // fallback with a different rate formula (build 152 mixed-speed
                        // regression). A dropped `<s>`/`<p>` boundary can be the ONLY
                        // thing separating two text nodes (VoiceOver sends the element
                        // name and its role as two adjacent `<s>` with nothing between
                        // them) — without a marker here the two nodes' text runs
                        // together into a single word, and the engine tokenizes purely
                        // on whitespace (`core/document.hpp:518-533`), so that glued run
                        // becomes one mispronounced token instead of two words
                        // (task-226 round 3). Other dropped tags (say-as, lang, prosody,
                        // sub, phoneme, emphasis, voice, mark, unknown …) sit INSIDE a
                        // single word/phrase, not between two text nodes — a marker
                        // there turns e.g. `<say-as>PDF</say-as>-файл` into
                        // "PDF -файл" (task-226 round 4).
                        output.append(droppedTagMarker)
                    }
                    tag.removeAll(keepingCapacity: true)
                    insideTag = false
                }
            } else if character == "<" {
                insideTag = true
                tag.append(character)
            } else {
                output.append(character)
            }
        }

        if insideTag {
            return nil
        }
        return resolvingDroppedTagMarkers(in: output)
    }

    /// Turns each `droppedTagMarker` into a single space when it sits between
    /// two non-whitespace characters, or into nothing otherwise (start/end of
    /// text, next to existing whitespace, or right before closing
    /// punctuation like `.`/`,` — a space there would read as an odd pause
    /// before the punctuation mark rather than fix any gluing). Consecutive
    /// markers left by several tags dropped in a row (e.g. `</lang></s><s>`)
    /// collapse into one decision, never several spaces.
    private static func resolvingDroppedTagMarkers(in text: String) -> String {
        let characters = Array(text)
        var output = ""
        output.reserveCapacity(characters.count)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            guard character == droppedTagMarker else {
                output.append(character)
                index += 1
                continue
            }

            var lookahead = index
            while lookahead < characters.count, characters[lookahead] == droppedTagMarker {
                lookahead += 1
            }
            let previous = output.last
            let next: Character? = lookahead < characters.count ? characters[lookahead] : nil
            if needsSeparatingSpace(previous: previous, next: next) {
                output.append(" ")
            }
            index = lookahead
        }

        return output
    }

    private static func needsSeparatingSpace(previous: Character?, next: Character?) -> Bool {
        guard let previous, let next, !isWhitespace(previous), !isWhitespace(next) else { return false }
        // A space right before `<` would sit between the preceding text and a
        // tag's opening bracket (e.g. a dropped-tag marker right before a
        // `<break/>` that follows immediately) — that reads as a spurious
        // double space once the tag's own separating logic adds its own space
        // on the other side (task-226 round 6, п.5).
        return next != "<" && !isClosingPunctuation(next)
    }

    private static func isClosingPunctuation(_ character: Character) -> Bool {
        ".,!?;:)]}»\"".contains(character)
    }

    private static func isPipelineWrapperTag(_ tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.range(of: #"^</?\s*(speak|prosody)\b"#, options: .regularExpression) != nil
    }

    private static func isPipelineBreakTag(_ tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.range(of: #"^<\s*break\b[^>]*/\s*>$"#, options: .regularExpression) != nil
    }

    // Only `<s>`/`<p>` (and their long-form spellings, in case a future
    // upstream sends them) sit BETWEEN two sibling text nodes with nothing
    // else in between. Every other dropped tag (say-as, lang, prosody, sub,
    // phoneme, emphasis, voice, mark, unknown …) sits INSIDE one text run —
    // marking those would insert a space in the middle of a word (task-226
    // round 4, e.g. `<say-as>PDF</say-as>-файл`).
    private static let sentenceOrParagraphBoundaryTagNames: Set<String> = [
        "s", "p", "sentence", "paragraph"
    ]

    private static func isSentenceOrParagraphBoundaryTag(_ tag: String) -> Bool {
        guard let parsed = parseSSMLTag(tag) else { return false }
        return sentenceOrParagraphBoundaryTagNames.contains(parsed.name)
    }

    private static func splitPipelineBodyIntoSentenceFragments(_ body: String) -> [FragmentBody] {
        var fragments: [String] = []
        var current = ""
        var tag = ""
        var insideTag = false
        var pendingBoundary = false
        var activeTags: [SSMLTag] = []
        let characters = Array(body)

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let suffix = activeTags.reversed().map(\.closingTag).joined()
                fragments.append(current + suffix)
            }
            current = activeTags.map(\.openingTag).joined()
            pendingBoundary = false
        }

        for index in characters.indices {
            let character = characters[index]

            if insideTag {
                tag.append(character)
                if character == ">" {
                    current += tag
                    updateActiveTags(with: tag, activeTags: &activeTags)
                    tag.removeAll(keepingCapacity: true)
                    insideTag = false
                }
                continue
            }

            if character == "<" {
                insideTag = true
                tag.append(character)
                continue
            }

            if pendingBoundary && !isWhitespace(character) {
                flushCurrent()
            }

            current.append(character)

            if isPipelineSentenceBoundary(character, in: characters, at: index) {
                pendingBoundary = true
            }
        }

        if insideTag {
            return [FragmentBody(text: body, continuesSentence: false)]
        }
        flushCurrent()
        return fragments.map { FragmentBody(text: $0, continuesSentence: false) }
    }

    private static func splitLongPipelineFragment(_ fragment: FragmentBody) -> [FragmentBody] {
        guard textCharacterCount(in: fragment.text) > 80 else { return [fragment] }

        var fragments: [FragmentBody] = []
        var current = ""
        var currentTextCount = 0
        var tag = ""
        var insideTag = false
        let characters = Array(fragment.text)

        func appendCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                current.removeAll(keepingCapacity: true)
                currentTextCount = 0
                return
            }

            if textCharacterCount(in: trimmed) < 15, !fragments.isEmpty {
                fragments[fragments.count - 1].text += " " + trimmed
            } else {
                let continuesSentence = !fragments.isEmpty || fragment.continuesSentence
                fragments.append(FragmentBody(text: trimmed, continuesSentence: continuesSentence))
            }

            current.removeAll(keepingCapacity: true)
            currentTextCount = 0
        }

        for index in characters.indices {
            let character = characters[index]

            if insideTag {
                tag.append(character)
                if character == ">" {
                    current += tag
                    tag.removeAll(keepingCapacity: true)
                    insideTag = false
                }
                continue
            }

            if character == "<" {
                insideTag = true
                tag.append(character)
                continue
            }

            current.append(character)
            currentTextCount += 1

            if currentTextCount >= 30,
               isPipelineSubSentenceBoundary(character, in: characters, at: index) {
                appendCurrent()
            }
        }

        if insideTag {
            return [fragment]
        }

        appendCurrent()
        return fragments.count > 1 ? fragments : [fragment]
    }

    private static func splitPriorityFirstFragment(_ fragments: [FragmentBody]) -> [FragmentBody] {
        guard let first = fragments.first,
              textCharacterCount(in: first.text) > 30,
              let splitIndex = priorityFirstFragmentSplitIndex(in: first.text) else {
            return fragments
        }

        let firstPart = first.text[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = first.text[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstPart.isEmpty, !remainder.isEmpty else { return fragments }

        return [
            FragmentBody(text: String(firstPart), continuesSentence: first.continuesSentence),
            FragmentBody(text: String(remainder), continuesSentence: true)
        ] + Array(fragments.dropFirst())
    }

    private static func priorityFirstFragmentSplitIndex(in fragment: String) -> String.Index? {
        var insideTag = false
        var textCount = 0
        var commaCandidates: [String.Index] = []
        var whitespaceCandidates: [String.Index] = []

        for index in fragment.indices {
            let character = fragment[index]

            if insideTag {
                if character == ">" { insideTag = false }
                continue
            }

            if character == "<" {
                insideTag = true
                continue
            }

            textCount += 1

            if (15...30).contains(textCount) {
                if character == "," {
                    commaCandidates.append(fragment.index(after: index))
                } else if isWhitespace(character) {
                    whitespaceCandidates.append(index)
                }
            }

            if textCount > 30 {
                break
            }
        }

        return commaCandidates.last ?? whitespaceCandidates.last
    }

    private static func isPipelineSentenceBoundary(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
    }

    private static func isPipelineSentenceBoundary(_ character: Character, in characters: [Character], at index: Int) -> Bool {
        guard isPipelineSentenceBoundary(character) else { return false }

        if character == ".",
           index > characters.startIndex {
            let nextIndex = characters.index(after: index)
            if nextIndex < characters.endIndex,
               isDigit(characters[characters.index(before: index)]),
               isDigit(characters[nextIndex]) {
                return false
            }
        }

        return true
    }

    private static func isPipelineSubSentenceBoundary(_ character: Character, in characters: [Character], at index: Int) -> Bool {
        guard character == "," || character == ";" || character == ":" || character == "—" else {
            return false
        }

        let nextIndex = characters.index(after: index)
        guard nextIndex < characters.endIndex else {
            return true
        }

        return isWhitespace(characters[nextIndex])
    }

    private static func mergeSmallPipelineFragments(_ fragments: [FragmentBody]) -> [FragmentBody] {
        var merged: [FragmentBody] = []

        for fragment in fragments {
            if !merged.isEmpty, textCharacterCount(in: fragment.text) < 10 {
                appendMergedFragmentText(&merged[merged.count - 1].text, fragment.text)
            } else {
                merged.append(fragment)
            }
        }

        if merged.count > 1, let last = merged.last, textCharacterCount(in: last.text) < 10 {
            appendMergedFragmentText(&merged[merged.count - 2].text, last.text)
            merged.removeLast()
        }

        return merged
    }

    // Mirrors `needsSeparatingSpace`/`resolvingDroppedTagMarkers`: gluing two
    // fragments at their raw text boundary (no tag was dropped here, the
    // fragments were just split) has the exact same "two non-space characters
    // meeting" problem — a long title ending mid-word plus a short next
    // fragment produced `новекнопка` as one token (task-226 round 4, п.2).
    private static func appendMergedFragmentText(_ base: inout String, _ addition: String) {
        if needsSeparatingSpace(previous: base.last, next: addition.first) {
            base += " "
        }
        base += addition
    }

    /// Drops every `<break .../>` in `text` that has no non-whitespace text
    /// on one of its sides WITHIN THIS FRAGMENT — such a tag is dead per
    /// FACT 4 (no text after: `core/language.cpp:1437-1442`, phrasify
    /// silently drops it) or FACT 5 (no text before: `core/document.hpp:
    /// 235-243`, the break command needs an already-created `TokStructure`,
    /// which only the first text token creates). Rather than rescuing it by
    /// merging fragments together (task-226 round 6 — this cascaded: with
    /// the sentence pause enabled, EVERY sentence ends in a break tag, so
    /// the merge chained the whole text back into one fragment), the tag is
    /// simply deleted. No pause is lost: the fragment boundary itself is a
    /// separate engine utterance, and `language::insert_pauses`
    /// (`core/language.cpp:1827-1838`) already puts a silence segment at the
    /// start and end of every utterance — the seam already has a pause
    /// without the tag (task-226 round 7).
    private static func removeOrphanedBreakTags(from text: String) -> OrphanBreakCleanup {
        guard text.range(of: #"<\s*break\b[^>]*/\s*>"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return OrphanBreakCleanup(text: text, removedLeadingOrphan: false, removedTrailingOrphan: false)
        }

        let characters = Array(text)
        var isTagCharacter = [Bool](repeating: false, count: characters.count)
        var scanningTag = false
        for index in characters.indices {
            if scanningTag {
                isTagCharacter[index] = true
                if characters[index] == ">" { scanningTag = false }
            } else if characters[index] == "<" {
                isTagCharacter[index] = true
                scanningTag = true
            }
        }

        var hasTextBefore = [Bool](repeating: false, count: characters.count + 1)
        for index in characters.indices {
            let isRealText = !isTagCharacter[index] && !isWhitespace(characters[index])
            hasTextBefore[index + 1] = hasTextBefore[index] || isRealText
        }
        var hasTextAfter = [Bool](repeating: false, count: characters.count + 1)
        for index in stride(from: characters.count - 1, through: 0, by: -1) {
            let isRealText = !isTagCharacter[index] && !isWhitespace(characters[index])
            hasTextAfter[index] = hasTextAfter[index + 1] || isRealText
        }

        var output = ""
        var insideTag = false
        var tagBuffer = ""
        var tagStart = 0
        var lastAppendedWasSpace = false
        var removedLeadingOrphan = false
        var removedTrailingOrphan = false

        for index in characters.indices {
            let character = characters[index]

            if insideTag {
                tagBuffer.append(character)
                if character == ">" {
                    let missingTextBefore = !hasTextBefore[tagStart]
                    let missingTextAfter = !hasTextAfter[index + 1]
                    let isOrphanedBreakTag = isPipelineBreakTag(tagBuffer)
                        && (missingTextBefore || missingTextAfter)
                    if isOrphanedBreakTag {
                        // Which side is missing tells us which fragment
                        // boundary the deleted tag's pause responsibility
                        // falls on: no text before it (FACT 5) means the tag
                        // sat at the START of THIS fragment, i.e. right after
                        // the seam with the PREVIOUS fragment; no text after
                        // (FACT 4) means it sat at the END, right before the
                        // seam with the NEXT fragment.
                        if missingTextBefore { removedLeadingOrphan = true }
                        if missingTextAfter { removedTrailingOrphan = true }
                    } else {
                        output += tagBuffer
                    }
                    tagBuffer.removeAll(keepingCapacity: true)
                    insideTag = false
                }
                continue
            }

            if character == "<" {
                insideTag = true
                tagStart = index
                tagBuffer.append(character)
                continue
            }

            if isWhitespace(character) {
                if !lastAppendedWasSpace {
                    output.append(" ")
                    lastAppendedWasSpace = true
                }
            } else {
                output.append(character)
                lastAppendedWasSpace = false
            }
        }

        return OrphanBreakCleanup(
            text: output.trimmingCharacters(in: .whitespacesAndNewlines),
            removedLeadingOrphan: removedLeadingOrphan,
            removedTrailingOrphan: removedTrailingOrphan
        )
    }

    private static func extractTextSegments(from ssml: String) -> [String] {
        var segments: [String] = []
        var textSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                if character == ">" {
                    insideTag = false
                }
            } else if character == "<" {
                if !textSegment.isEmpty {
                    segments.append(textSegment)
                    textSegment.removeAll(keepingCapacity: true)
                }
                insideTag = true
            } else {
                textSegment.append(character)
            }
        }

        if !textSegment.isEmpty {
            segments.append(textSegment)
        }
        return segments
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func logSSMLTagNames(from ssml: String) {
        #if DEBUG
        let names = ssmlTagNames(from: ssml)
        let tagList = names.isEmpty ? "none" : names.joined(separator: ",")
        os_log(.info, log: diagnosticLog, "LATENCY_DIAG ssml tags=%@", tagList)
        #endif
    }

    private static func logPipelinePlan(fragmentCount: Int, totalLength: Int) {
        #if DEBUG
        os_log(.info, log: diagnosticLog, "LATENCY_DIAG pipeline plan fragments=%d totalLen=%d", fragmentCount, totalLength)
        #endif
    }

    private static func ssmlTagNames(from ssml: String) -> [String] {
        var names = Set<String>()
        var tag = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tag.append(character)
                if character == ">" {
                    if let parsed = parseSSMLTag(tag) {
                        names.insert(parsed.name)
                    }
                    tag.removeAll(keepingCapacity: true)
                    insideTag = false
                }
            } else if character == "<" {
                insideTag = true
                tag.append(character)
            }
        }

        return names.sorted()
    }

    private static func updateActiveTags(with tag: String, activeTags: inout [SSMLTag]) {
        guard let parsed = parseSSMLTag(tag),
              !parsed.isSelfClosing else {
            return
        }

        if parsed.isClosing {
            if let index = activeTags.lastIndex(where: { $0.name == parsed.name }) {
                activeTags.removeSubrange(index...)
            }
        } else {
            activeTags.append(SSMLTag(name: parsed.name, openingTag: tag, closingTag: "</\(parsed.name)>"))
        }
    }

    private static func parseSSMLTag(_ tag: String) -> ParsedSSMLTag? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return nil }

        var content = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let isClosing = content.hasPrefix("/")
        if isClosing {
            content = content.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let isSelfClosing = !isClosing && content.hasSuffix("/")
        if isSelfClosing {
            content = content.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let nameEnd = content.firstIndex(where: { isWhitespace($0) || $0 == "/" }),
              nameEnd > content.startIndex else {
            let name = String(content).lowercased()
            return name.isEmpty ? nil : ParsedSSMLTag(name: name, isClosing: isClosing, isSelfClosing: isSelfClosing)
        }

        let name = String(content[..<nameEnd]).lowercased()
        return name.isEmpty ? nil : ParsedSSMLTag(name: name, isClosing: isClosing, isSelfClosing: isSelfClosing)
    }

    private struct SSMLTag {
        let name: String
        let openingTag: String
        let closingTag: String
    }

    private struct FragmentBody {
        var text: String
        var continuesSentence: Bool
    }

    /// Result of `removeOrphanedBreakTags`: the cleaned fragment text, plus
    /// which edge(s) of the fragment lost a break tag that relied on
    /// `insert_pauses`'s own seam silence (task-226 round 8) — see the call
    /// site in `pipelineFragments` for how this feeds back into
    /// `continuesSentence` on the neighboring fragment.
    private struct OrphanBreakCleanup {
        let text: String
        let removedLeadingOrphan: Bool
        let removedTrailingOrphan: Bool
    }

    private struct ParsedSSMLTag {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
    }
}
