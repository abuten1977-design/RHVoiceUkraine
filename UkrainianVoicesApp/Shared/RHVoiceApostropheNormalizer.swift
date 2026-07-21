import Foundation

enum RHVoiceApostropheNormalizer {
    static let engineApostrophe = "\u{0027}"

    static func normalizeStandaloneApostropheRequest(_ ssml: String) -> String? {
        let text = extractTextSegments(from: ssml).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return spokenStandaloneApostropheName(for: text)
    }

    static func normalizeInTextSegments(_ ssml: String) -> String {
        let ssml = normalizeTelephoneSayAsBlocks(in: normalizeSplitDateSayAsBlocks(in: ssml))
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
        normalizeNumbers(in: normalizeDates(in: normalizeText(text)))
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
            pattern: #"(?<![\p{L}\p{N}/])([0-9]{1,12})/([0-9]{1,12})(?![\p{L}\p{N}/])"#
        ) { match in
            guard
                let numeratorRange = Range(match.range(at: 1), in: withMixedFractions),
                let denominatorRange = Range(match.range(at: 2), in: withMixedFractions),
                let numerator = Int(String(withMixedFractions[numeratorRange])),
                let denominator = Int(String(withMixedFractions[denominatorRange]))
            else { return nil }

            return "\(integerToWords(numerator)) дріб \(integerToWords(denominator))"
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
            pattern: #"(?<![\p{L}\p{N}.,])([0-9]{5,12})(?![\p{L}\p{N}.,])"#
        ) { match in
            guard
                let range = Range(match.range(at: 1), in: withDecimals),
                let value = Int(String(withDecimals[range]))
            else { return nil }

            return integerToWords(value)
        }
    }

    private static func normalizeDates(in text: String) -> String {
        // iOS 26 VoiceOver віддає дати з ОЗВУЧЕНИМИ крапками: «10 крапка 07 крапка 2026»
        // (крапки замінені словом ще ДО синтезатора — доведено логом пристрою 2026-07-21).
        // Розпізнаємо цю форму першою; валідність перевіряє dateToWords, тож
        // «32 крапка 07 крапка 2026» лишається числами, а «1 крапка 16.4» не
        // збігається взагалі (потрібні ДВІ «крапки» між числами).
        let withVerbalizedDots = replacingMatches(
            in: text,
            pattern: #"(?<![\p{L}\p{N}.,])([0-9]{1,2})\s+крапка\s+([0-9]{1,2})\s+крапка\s+([1-2][0-9]{3})(?![\p{L}\p{N}]|[.,][0-9])"#,
            options: [.caseInsensitive]
        ) { match, source in
            dateMatchToWords(match, in: source)
        }

        return replacingMatches(
            in: withVerbalizedDots,
            pattern: #"(?<![\p{L}\p{N}.,])([0-9]{1,2})\.([0-9]{1,2})\.([1-2][0-9]{3})(?![\p{L}\p{N}]|[.,][0-9])"#,
            options: []
        ) { match, source in
            dateMatchToWords(match, in: source)
        }
    }

    private static func normalizeSplitDateSayAsBlocks(in ssml: String) -> String {
        let dateComponent = #"(?:[0-9]{1,4}|<say-as\b[^>]*>\s*[0-9]{1,4}\s*</say-as>)"#
        let pattern = #"(?<![\p{L}\p{N}.,])("# + dateComponent + #")\.("# + dateComponent + #")\.("# + dateComponent + #")(?![\p{L}\p{N}]|[.,][0-9])"#

        return replacingMatches(
            in: ssml,
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) { match, source in
            guard
                let dayRange = Range(match.range(at: 1), in: source),
                let monthRange = Range(match.range(at: 2), in: source),
                let yearRange = Range(match.range(at: 3), in: source),
                let day = dateComponentValue(String(source[dayRange])),
                let month = dateComponentValue(String(source[monthRange])),
                let year = dateComponentValue(String(source[yearRange]))
            else { return nil }

            return dateToWords(day: day, month: month, year: year)
        }
    }

    private static func dateComponentValue(_ component: String) -> Int? {
        let text = extractTextSegments(from: component).joined()
        let digits = (text.isEmpty ? component : text).filter(\.isNumber)
        return Int(digits)
    }

    private static func normalizeTelephoneSayAsBlocks(in ssml: String) -> String {
        let withSplitDecimals = replacingMatches(
            in: ssml,
            pattern: #"([0-9]+),\s*<say-as\b(?=[^>]*\binterpret-as\s*=\s*["']telephone["'])[^>]*>\s*([0-9]+)\s*</say-as>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) { match, source in
            guard
                let integerRange = Range(match.range(at: 1), in: source),
                let fractionRange = Range(match.range(at: 2), in: source)
            else { return nil }

            return decimalNumberToWords(integerPart: String(source[integerRange]), fractionPart: String(source[fractionRange]))
        }

        return replacingMatches(
            in: withSplitDecimals,
            pattern: #"<say-as\b(?=[^>]*\binterpret-as\s*=\s*["']telephone["'])[^>]*>(.*?)</say-as>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) { match, source in
            guard let contentRange = Range(match.range(at: 1), in: source) else { return nil }

            let content = String(source[contentRange])
            if let dateWords = dateStringToWords(content) {
                return dateWords
            }

            let digits = content.filter(\.isNumber)
            guard !digits.isEmpty else { return normalizeText(content) }

            let isTelephone = content.contains("+") || hasDigitSeparator(in: content) || digits.count >= 10
            if isTelephone {
                return telephoneDigitsToWords(content)
            }

            guard let value = Int(digits) else { return nil }
            return integerToWords(value)
        }
    }

    private static func dateMatchToWords(_ match: NSTextCheckingResult, in text: String) -> String? {
        guard
            let dayRange = Range(match.range(at: 1), in: text),
            let monthRange = Range(match.range(at: 2), in: text),
            let yearRange = Range(match.range(at: 3), in: text),
            let day = Int(String(text[dayRange])),
            let month = Int(String(text[monthRange])),
            let year = Int(String(text[yearRange]))
        else { return nil }

        return dateToWords(day: day, month: month, year: year)
    }

    private static func dateStringToWords(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([0-9]{1,2})\.([0-9]{1,2})\.([1-2][0-9]{3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: nsRange) else { return nil }
        return dateMatchToWords(match, in: trimmed)
    }

    private static func dateToWords(day: Int, month: Int, year: Int) -> String? {
        guard
            (1...31).contains(day),
            (1...12).contains(month),
            (1000...2999).contains(year),
            let dayWords = dayOrdinalNeuter(day),
            let yearWords = yearOrdinalGenitive(year)
        else { return nil }

        let months = [
            "січня", "лютого", "березня", "квітня", "травня", "червня",
            "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
        ]

        return "\(dayWords) \(months[month - 1]) \(yearWords) року"
    }

    private static func dayOrdinalNeuter(_ day: Int) -> String? {
        let names = [
            1: "перше",
            2: "друге",
            3: "третє",
            4: "четверте",
            5: "п'яте",
            6: "шосте",
            7: "сьоме",
            8: "восьме",
            9: "дев'яте",
            10: "десяте",
            11: "одинадцяте",
            12: "дванадцяте",
            13: "тринадцяте",
            14: "чотирнадцяте",
            15: "п'ятнадцяте",
            16: "шістнадцяте",
            17: "сімнадцяте",
            18: "вісімнадцяте",
            19: "дев'ятнадцяте",
            20: "двадцяте",
            30: "тридцяте"
        ]

        if let name = names[day] {
            return name
        }

        guard (21...31).contains(day), let unit = names[day % 10] else { return nil }
        return "\(underThousandToWords((day / 10) * 10, feminine: false)) \(unit)"
    }

    private static func yearOrdinalGenitive(_ year: Int) -> String? {
        switch year {
        case 1000:
            return "тисячного"
        case 2000:
            return "двохтисячного"
        case 1001...1999:
            guard let rest = underThousandOrdinalGenitive(year - 1000) else { return nil }
            return "тисяча \(rest)"
        case 2001...2999:
            guard let rest = underThousandOrdinalGenitive(year - 2000) else { return nil }
            return "дві тисячі \(rest)"
        default:
            return nil
        }
    }

    private static func underThousandOrdinalGenitive(_ value: Int) -> String? {
        guard (1...999).contains(value) else { return nil }

        let unitNames = [
            1: "першого",
            2: "другого",
            3: "третього",
            4: "четвертого",
            5: "п'ятого",
            6: "шостого",
            7: "сьомого",
            8: "восьмого",
            9: "дев'ятого"
        ]
        let teenNames = [
            10: "десятого",
            11: "одинадцятого",
            12: "дванадцятого",
            13: "тринадцятого",
            14: "чотирнадцятого",
            15: "п'ятнадцятого",
            16: "шістнадцятого",
            17: "сімнадцятого",
            18: "вісімнадцятого",
            19: "дев'ятнадцятого"
        ]
        let tensNames = [
            20: "двадцятого",
            30: "тридцятого",
            40: "сорокового",
            50: "п'ятдесятого",
            60: "шістдесятого",
            70: "сімдесятого",
            80: "вісімдесятого",
            90: "дев'яностого"
        ]
        let hundredsNames = [
            100: "сотого",
            200: "двохсотого",
            300: "трьохсотого",
            400: "чотирьохсотого",
            500: "п'ятисотого",
            600: "шестисотого",
            700: "семисотого",
            800: "восьмисотого",
            900: "дев'ятисотого"
        ]

        if let name = unitNames[value] ?? teenNames[value] ?? tensNames[value] ?? hundredsNames[value] {
            return name
        }

        if value < 100 {
            let tens = (value / 10) * 10
            guard let unit = unitNames[value % 10] else { return nil }
            return "\(underThousandToWords(tens, feminine: false)) \(unit)"
        }

        let hundreds = (value / 100) * 100
        let rest = value % 100
        guard let restWords = underThousandOrdinalGenitive(rest) else { return nil }
        return "\(underThousandToWords(hundreds, feminine: false)) \(restWords)"
    }

    private static func decimalNumberToWords(integerPart: String, fractionPart: String) -> String? {
        guard
            let integerValue = Int(integerPart),
            let fractionValue = Int(fractionPart),
            fractionValue != 0
        else { return nil }

        let integerWords = integerToWords(integerValue, feminineLastGroup: true)
        let wholePartName = nounForm(for: integerValue, one: "ціла", few: "цілих", many: "цілих")
        let fractionWords = integerToWords(fractionValue, feminineLastGroup: true)
        let denominator = fractionalDenominatorName(digitCount: fractionPart.count, value: fractionValue)

        return "\(integerWords) \(wholePartName) \(fractionWords) \(denominator)"
    }

    private static func hasDigitSeparator(in text: String) -> Bool {
        let pattern = #"[0-9][\s\-()]+[0-9]"#
        return (try? NSRegularExpression(pattern: pattern))
            .map { regex in
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                return regex.firstMatch(in: text, range: nsRange) != nil
            } ?? false
    }

    private static func telephoneDigitsToWords(_ text: String) -> String {
        let digitWords: [Character: String] = [
            "0": "нуль",
            "1": "один",
            "2": "два",
            "3": "три",
            "4": "чотири",
            "5": "п'ять",
            "6": "шість",
            "7": "сім",
            "8": "вісім",
            "9": "дев'ять"
        ]

        var words: [String] = []
        for character in text {
            if character == "+" {
                words.append("плюс")
            } else if let word = digitWords[character] {
                words.append(word)
            }
        }

        return words.joined(separator: " ")
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

    private static func replacingMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options,
        transform: (NSTextCheckingResult, String) -> String?
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange).reversed()
        var result = text

        for match in matches {
            guard let replacement = transform(match, text), let range = Range(match.range, in: result) else {
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
