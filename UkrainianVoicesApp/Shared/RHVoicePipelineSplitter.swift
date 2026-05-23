import Foundation

enum RHVoicePipelineSplitter {
    static func sentencePipelineFragments(from ssml: String) -> [String] {
        guard let strippedBody = pipelineBodyByRemovingWrapperTags(from: ssml) else {
            return [ssml]
        }
        let bodyFragments = splitPipelineBodyIntoSentenceFragments(strippedBody)
        let pipelineFragments = bodyFragments.flatMap { splitLongPipelineFragment($0) }
        guard pipelineFragments.count > 1 else { return [ssml] }

        let mergedFragments = mergeSmallPipelineFragments(pipelineFragments)
        guard mergedFragments.count > 1,
              mergedFragments.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return [ssml]
        }

        return mergedFragments.map { "<speak>\($0)</speak>" }
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
                    } else if !isPipelineWrapperTag(tag) {
                        return nil
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

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                fragments.append(current)
            }
            current.removeAll(keepingCapacity: true)
            pendingBoundary = false
        }

        for character in body {
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

            if pendingBoundary && !isWhitespace(character) {
                flushCurrent()
            }

            current.append(character)

            if isPipelineSentenceBoundary(character) {
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

    private static func isPipelineSentenceBoundary(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
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
}
