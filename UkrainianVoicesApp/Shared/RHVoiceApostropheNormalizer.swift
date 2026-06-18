import Foundation

enum RHVoiceApostropheNormalizer {
    static let engineApostrophe = "\u{0027}"
    private static let spokenStandaloneApostrophe = "апостроф"

    static func normalizeStandaloneApostropheRequest(_ ssml: String) -> String? {
        let text = extractTextSegments(from: ssml).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return normalizeText(text) == engineApostrophe ? spokenStandaloneApostrophe : nil
    }

    static func normalizeInTextSegments(_ ssml: String) -> String {
        var output = ""
        var textSegment = ""
        var tagSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tagSegment.append(character)
                if character == ">" {
                    output += normalizeText(textSegment)
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
            output += normalizeText(textSegment) + tagSegment
        } else {
            output += normalizeText(textSegment)
        }
        return output
    }

    static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&apos;", with: engineApostrophe)
            .replacingOccurrences(of: "&#39;", with: engineApostrophe)
            .replacingOccurrences(of: "&#x27;", with: engineApostrophe)
            .replacingOccurrences(of: "&#X27;", with: engineApostrophe)
            .replacingOccurrences(of: "\u{0027}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{2019}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{2018}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{2032}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{02BC}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{00B4}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{FF07}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{0060}", with: engineApostrophe)
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
}
