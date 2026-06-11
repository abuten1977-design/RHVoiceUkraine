import Foundation
import os.log

enum RHVoicePipelineSplitter {
    private static let diagnosticLog = OSLog(subsystem: "com.rhvoice.UkrainianVoices", category: "latency")

    static func sentencePipelineFragments(from ssml: String) -> [String] {
        logSSMLTagNames(from: ssml)

        guard let strippedBody = pipelineBodyByRemovingWrapperTags(from: ssml) else {
            logPipelinePlan(fragmentCount: 1, totalLength: ssml.count)
            return [ssml]
        }
        // Single-fragment fallbacks must also go through the cleaned body: returning
        // the original ssml (with unknown tags) would send short texts down the
        // engine's plain-text fallback with a different rate formula than split
        // fragments use — short and long texts must sound identical.
        let cleanedWholeUtterance: [String] = {
            let trimmed = strippedBody.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [ssml] : ["<speak>\(strippedBody)</speak>"]
        }()
        let bodyFragments = splitPipelineBodyIntoSentenceFragments(strippedBody)
        let pipelineFragments = bodyFragments.flatMap { splitLongPipelineFragment($0) }
        let priorityFragments = splitPriorityFirstFragment(pipelineFragments)
        guard priorityFragments.count > 1 else {
            logPipelinePlan(fragmentCount: 1, totalLength: ssml.count)
            return cleanedWholeUtterance
        }

        let mergedFragments = mergeSmallPipelineFragments(priorityFragments)
        guard mergedFragments.count > 1,
              mergedFragments.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            logPipelinePlan(fragmentCount: 1, totalLength: ssml.count)
            return cleanedWholeUtterance
        }

        let fragments = mergedFragments.map { "<speak>\($0)</speak>" }
        logPipelinePlan(fragmentCount: fragments.count, totalLength: ssml.count)
        return fragments
    }

    static func textCharacterCount(in ssml: String) -> Int {
        extractTextSegments(from: ssml)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count
    }

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
                    }
                    // speak/prosody wrappers and unknown (VoiceOver service) tags are
                    // dropped, keeping their inner text: the engine rejects unknown
                    // tags, which triggered the per-fragment plain-text fallback with
                    // a different rate formula (build 152 mixed-speed regression).
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
        return output
    }

    private static func isPipelineWrapperTag(_ tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.range(of: #"^</?\s*(speak|prosody)\b"#, options: .regularExpression) != nil
    }

    private static func isPipelineBreakTag(_ tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.range(of: #"^<\s*break\b[^>]*/\s*>$"#, options: .regularExpression) != nil
    }

    private static func splitPipelineBodyIntoSentenceFragments(_ body: String) -> [String] {
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
            return [body]
        }
        flushCurrent()
        return fragments
    }

    private static func splitLongPipelineFragment(_ fragment: String) -> [String] {
        guard textCharacterCount(in: fragment) > 80 else { return [fragment] }

        var fragments: [String] = []
        var current = ""
        var currentTextCount = 0
        var tag = ""
        var insideTag = false
        let characters = Array(fragment)

        func appendCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                current.removeAll(keepingCapacity: true)
                currentTextCount = 0
                return
            }

            if textCharacterCount(in: trimmed) < 15, !fragments.isEmpty {
                fragments[fragments.count - 1] += " " + trimmed
            } else {
                fragments.append(trimmed)
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

    private static func splitPriorityFirstFragment(_ fragments: [String]) -> [String] {
        guard let first = fragments.first,
              textCharacterCount(in: first) > 30,
              let splitIndex = priorityFirstFragmentSplitIndex(in: first) else {
            return fragments
        }

        let firstPart = first[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = first[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstPart.isEmpty, !remainder.isEmpty else { return fragments }

        return [String(firstPart), String(remainder)] + Array(fragments.dropFirst())
    }

    private static func priorityFirstFragmentSplitIndex(in fragment: String) -> String.Index? {
        var insideTag = false
        var textCount = 0
        var commaCandidate: String.Index?
        var whitespaceCandidate: String.Index?

        for index in fragment.indices {
            let character = fragment[index]

            if insideTag {
                if character == ">" {
                    insideTag = false
                }
                continue
            }

            if character == "<" {
                insideTag = true
                continue
            }

            textCount += 1

            if (15...30).contains(textCount) {
                if character == "," {
                    commaCandidate = fragment.index(after: index)
                } else if isWhitespace(character) {
                    whitespaceCandidate = index
                }
            }

            if textCount > 30 {
                break
            }
        }

        return commaCandidate ?? whitespaceCandidate
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

    private static func mergeSmallPipelineFragments(_ fragments: [String]) -> [String] {
        var merged: [String] = []

        for fragment in fragments {
            if textCharacterCount(in: fragment) < 10, !merged.isEmpty {
                merged[merged.count - 1] += fragment
            } else {
                merged.append(fragment)
            }
        }

        if merged.count > 1, let last = merged.last, textCharacterCount(in: last) < 10 {
            merged[merged.count - 2] += last
            merged.removeLast()
        }

        return merged
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
        let names = ssmlTagNames(from: ssml)
        let tagList = names.isEmpty ? "none" : names.joined(separator: ",")
        os_log(.info, log: diagnosticLog, "LATENCY_DIAG ssml tags=%{public}@", tagList)
    }

    private static func logPipelinePlan(fragmentCount: Int, totalLength: Int) {
        os_log(.info, log: diagnosticLog, "LATENCY_DIAG pipeline plan fragments=%{public}d totalLen=%{public}d", fragmentCount, totalLength)
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

    private struct ParsedSSMLTag {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
    }
}
