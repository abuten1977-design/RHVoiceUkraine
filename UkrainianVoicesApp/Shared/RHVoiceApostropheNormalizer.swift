import Foundation

enum RHVoiceApostropheNormalizer {
    static let engineApostrophe = "\u{0027}"

    static func normalizeStandaloneApostropheRequest(_ ssml: String) -> String? {
        let text = extractTextSegments(from: ssml).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return spokenStandaloneApostropheName(for: text)
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
                    output += normalizeTextSegment(textSegment)
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
            output += normalizeTextSegment(textSegment) + tagSegment
        } else {
            output += normalizeTextSegment(textSegment)
        }
        return output
    }

    static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&apos;", with: engineApostrophe)
            .replacingOccurrences(of: "&#39;", with: engineApostrophe)
            .replacingOccurrences(of: "&#x27;", with: engineApostrophe)
            .replacingOccurrences(of: "&#X27;", with: engineApostrophe)
            .replacingOccurrences(of: "&#96;", with: engineApostrophe)
            .replacingOccurrences(of: "&#x60;", with: engineApostrophe)
            .replacingOccurrences(of: "&#X60;", with: engineApostrophe)
            .replacingOccurrences(of: "&grave;", with: engineApostrophe)
            .replacingOccurrences(of: "\u{0027}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{2019}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{2018}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{2032}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{02BC}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{00B4}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{FF07}", with: engineApostrophe)
            .replacingOccurrences(of: "\u{0060}", with: engineApostrophe)
    }

    private static func normalizeTextSegment(_ text: String) -> String {
        normalizeNumbers(in: normalizeText(text))
    }

    private static func spokenStandaloneApostropheName(for text: String) -> String? {
        switch text {
        case "'", "&apos;", "&#39;", "&#x27;", "&#X27;":
            return "прямий апостроф"
        case "\u{2019}":
            return "правий апостроф"
        case "\u{2018}":
            return "лівий апостроф"
        case "\u{02BC}":
            return "буквений апостроф"
        case "\u{0060}", "&#96;", "&#x60;", "&#X60;", "&grave;":
            return "зворотний апостроф"
        case "\u{2032}":
            return "штрих"
        case "\u{00B4}":
            return "акут"
        case "\u{FF07}":
            return "повноширинний апостроф"
        default:
            return nil
        }
    }

    private static func normalizeNumbers(in text: String) -> String {
        let withMixedFractions = replacingMatches(
            in: text,
            pattern: #"(?<![\p{L}\p{N}/])([0-9]{1,12})\s+цілих\s+([0-9]{1,3})/([0-9]{1,3})(?![\p{L}\p{N}/])"#
        ) { match in
            guard
                let integerRange = Range(match.range(at: 1), in: text),
                let numeratorRange = Range(match.range(at: 2), in: text),
                let denominatorRange = Range(match.range(at: 3), in: text),
                let integerValue = Int(String(text[integerRange])),
                let numerator = Int(String(text[numeratorRange])),
                let denominator = Int(String(text[denominatorRange])),
                let fractionWords = simpleFractionToWords(numerator: numerator, denominator: denominator)
            else { return nil }

            let integerWords = integerToWords(integerValue, feminineLastGroup: true)
            let wholePartName = nounForm(for: integerValue, one: "ціла", few: "цілих", many: "цілих")
            return "\(integerWords) \(wholePartName) \(fractionWords)"
        }

        let withSimpleFractions = replacingMatches(
            in: withMixedFractions,
            pattern: #"(?<![\p{L}\p{N}/])([0-9]{1,3})/([0-9]{1,3})(?![\p{L}\p{N}/])"#
        ) { match in
            guard
                let numeratorRange = Range(match.range(at: 1), in: withMixedFractions),
                let denominatorRange = Range(match.range(at: 2), in: withMixedFractions),
                let numerator = Int(String(withMixedFractions[numeratorRange])),
                let denominator = Int(String(withMixedFractions[denominatorRange]))
            else { return nil }

            return simpleFractionToWords(numerator: numerator, denominator: denominator)
        }

        let withDecimals = replacingMatches(
            in: withSimpleFractions,
            pattern: #"(?<![\p{L}\p{N}])([0-9]{1,12}),([0-9]{1,12})(?![\p{L}\p{N}])"#
        ) { match in
            guard
                let integerRange = Range(match.range(at: 1), in: withSimpleFractions),
                let fractionRange = Range(match.range(at: 2), in: withSimpleFractions),
                let integerValue = Int(String(withSimpleFractions[integerRange]))
            else { return nil }

            let fractionDigits = String(withSimpleFractions[fractionRange])
            guard let fractionValue = Int(fractionDigits), fractionValue != 0 else { return nil }

            let integerWords = integerToWords(integerValue, feminineLastGroup: true)
            let wholePartName = nounForm(for: integerValue, one: "ціла", few: "цілих", many: "цілих")
            let fractionWords = integerToWords(fractionValue, feminineLastGroup: true)
            let denominator = fractionalDenominatorName(digitCount: fractionDigits.count, value: fractionValue)

            return "\(integerWords) \(wholePartName) \(fractionWords) \(denominator)"
        }

        return replacingMatches(
            in: withDecimals,
            pattern: #"(?<![\p{L}\p{N}.,])([0-9]{6,12})(?![\p{L}\p{N}.,])"#
        ) { match in
            guard
                let range = Range(match.range(at: 1), in: withDecimals),
                let value = Int(String(withDecimals[range]))
            else { return nil }

            return integerToWords(value)
        }
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        transform: (NSTextCheckingResult) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()
        var result = text

        for match in matches {
            guard let replacement = transform(match), let range = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(range, with: replacement)
        }

        return result
    }

    private static func integerToWords(_ value: Int, feminineLastGroup: Bool = false) -> String {
        guard value != 0 else { return "нуль" }
        guard value > 0 else { return "мінус \(integerToWords(abs(value), feminineLastGroup: feminineLastGroup))" }

        let groups = [
            (1_000_000_000, "мільярд", "мільярди", "мільярдів", false),
            (1_000_000, "мільйон", "мільйони", "мільйонів", false),
            (1_000, "тисяча", "тисячі", "тисяч", true)
        ]

        var remainder = value
        var parts: [String] = []

        for group in groups {
            let count = remainder / group.0
            guard count > 0 else { continue }

            parts.append(underThousandToWords(count, feminine: group.4))
            parts.append(nounForm(for: count, one: group.1, few: group.2, many: group.3))
            remainder %= group.0
        }

        if remainder > 0 {
            parts.append(underThousandToWords(remainder, feminine: feminineLastGroup))
        }

        return parts.joined(separator: " ")
    }

    private static func underThousandToWords(_ value: Int, feminine: Bool) -> String {
        let hundreds = [
            "", "сто", "двісті", "триста", "чотириста",
            "п'ятсот", "шістсот", "сімсот", "вісімсот", "дев'ятсот"
        ]
        let tens = [
            "", "", "двадцять", "тридцять", "сорок",
            "п'ятдесят", "шістдесят", "сімдесят", "вісімдесят", "дев'яносто"
        ]
        let teens = [
            "десять", "одинадцять", "дванадцять", "тринадцять", "чотирнадцять",
            "п'ятнадцять", "шістнадцять", "сімнадцять", "вісімнадцять", "дев'ятнадцять"
        ]
        let unitsMasculine = ["", "один", "два", "три", "чотири", "п'ять", "шість", "сім", "вісім", "дев'ять"]
        let unitsFeminine = ["", "одна", "дві", "три", "чотири", "п'ять", "шість", "сім", "вісім", "дев'ять"]

        var parts: [String] = []
        let hundred = value / 100
        let rest = value % 100

        if hundred > 0 {
            parts.append(hundreds[hundred])
        }

        if (10...19).contains(rest) {
            parts.append(teens[rest - 10])
        } else {
            let ten = rest / 10
            let unit = rest % 10
            if ten > 0 {
                parts.append(tens[ten])
            }
            if unit > 0 {
                parts.append((feminine ? unitsFeminine : unitsMasculine)[unit])
            }
        }

        return parts.joined(separator: " ")
    }

    private static func fractionalDenominatorName(digitCount: Int, value: Int) -> String {
        switch digitCount {
        case 1:
            return nounForm(for: value, one: "десята", few: "десятих", many: "десятих")
        case 2:
            return nounForm(for: value, one: "сота", few: "сотих", many: "сотих")
        case 3:
            return nounForm(for: value, one: "тисячна", few: "тисячних", many: "тисячних")
        case 4:
            return nounForm(for: value, one: "десятитисячна", few: "десятитисячних", many: "десятитисячних")
        case 5:
            return nounForm(for: value, one: "стотисячна", few: "стотисячних", many: "стотисячних")
        case 6:
            return nounForm(for: value, one: "мільйонна", few: "мільйонних", many: "мільйонних")
        case 7:
            return nounForm(for: value, one: "десятимільйонна", few: "десятимільйонних", many: "десятимільйонних")
        case 8:
            return nounForm(for: value, one: "стомільйонна", few: "стомільйонних", many: "стомільйонних")
        case 9:
            return nounForm(for: value, one: "мільярдна", few: "мільярдних", many: "мільярдних")
        case 10:
            return nounForm(for: value, one: "десятимільярдна", few: "десятимільярдних", many: "десятимільярдних")
        case 11:
            return nounForm(for: value, one: "стомільярдна", few: "стомільярдних", many: "стомільярдних")
        case 12:
            return nounForm(for: value, one: "трильйонна", few: "трильйонних", many: "трильйонних")
        default:
            return ""
        }
    }

    private static func simpleFractionToWords(numerator: Int, denominator: Int) -> String? {
        guard numerator > 0, denominator > 1 else { return nil }
        guard let denominatorWords = simpleFractionDenominatorName(denominator, numerator: numerator) else {
            return nil
        }

        return "\(integerToWords(numerator, feminineLastGroup: true)) \(denominatorWords)"
    }

    private static func simpleFractionDenominatorName(_ denominator: Int, numerator: Int) -> String? {
        guard denominator > 1, denominator < 100 else { return nil }

        let useSingular = usesSingularFractionDenominator(for: numerator)

        if denominator < 20 {
            let names = [
                2: ("друга", "других"),
                3: ("третя", "третіх"),
                4: ("четверта", "четвертих"),
                5: ("п'ята", "п'ятих"),
                6: ("шоста", "шостих"),
                7: ("сьома", "сьомих"),
                8: ("восьма", "восьмих"),
                9: ("дев'ята", "дев'ятих"),
                10: ("десята", "десятих"),
                11: ("одинадцята", "одинадцятих"),
                12: ("дванадцята", "дванадцятих"),
                13: ("тринадцята", "тринадцятих"),
                14: ("чотирнадцята", "чотирнадцятих"),
                15: ("п'ятнадцята", "п'ятнадцятих"),
                16: ("шістнадцята", "шістнадцятих"),
                17: ("сімнадцята", "сімнадцятих"),
                18: ("вісімнадцята", "вісімнадцятих"),
                19: ("дев'ятнадцята", "дев'ятнадцятих")
            ]
            guard let forms = names[denominator] else { return nil }
            return useSingular ? forms.0 : forms.1
        }

        if denominator % 10 == 0 {
            let names = [
                20: ("двадцята", "двадцятих"),
                30: ("тридцята", "тридцятих"),
                40: ("сорокова", "сорокових"),
                50: ("п'ятдесята", "п'ятдесятих"),
                60: ("шістдесята", "шістдесятих"),
                70: ("сімдесята", "сімдесятих"),
                80: ("вісімдесята", "вісімдесятих"),
                90: ("дев'яноста", "дев'яностих")
            ]
            guard let forms = names[denominator] else { return nil }
            return useSingular ? forms.0 : forms.1
        }

        let tensWords = underThousandToWords((denominator / 10) * 10, feminine: false)
        let unit = denominator % 10
        let unitNames = [
            1: ("перша", "перших"),
            2: ("друга", "других"),
            3: ("третя", "третіх"),
            4: ("четверта", "четвертих"),
            5: ("п'ята", "п'ятих"),
            6: ("шоста", "шостих"),
            7: ("сьома", "сьомих"),
            8: ("восьма", "восьмих"),
            9: ("дев'ята", "дев'ятих")
        ]
        guard let forms = unitNames[unit] else { return nil }
        return "\(tensWords) \(useSingular ? forms.0 : forms.1)"
    }

    private static func usesSingularFractionDenominator(for numerator: Int) -> Bool {
        let lastTwo = abs(numerator) % 100
        let last = abs(numerator) % 10
        return last == 1 && !(11...14).contains(lastTwo)
    }

    private static func nounForm(for value: Int, one: String, few: String, many: String) -> String {
        let lastTwo = abs(value) % 100
        let last = abs(value) % 10

        if (11...14).contains(lastTwo) {
            return many
        }
        if last == 1 {
            return one
        }
        if (2...4).contains(last) {
            return few
        }
        return many
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
