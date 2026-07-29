import XCTest

final class RHVoiceApostropheNormalizerTests: XCTestCase {
    func testApostropheVariantsNormalizeToAsciiApostrophe() {
        let variants = [
            "&apos;",
            "&#39;",
            "&#x27;",
            "&#X27;",
            "&#96;",
            "&#x60;",
            "&#X60;",
            "&grave;",
            "\u{0027}",
            "\u{2019}",
            "\u{2018}",
            "\u{2032}",
            "\u{02BC}",
            "\u{00B4}",
            "\u{FF07}",
            "\u{0060}"
        ]

        for variant in variants {
            XCTAssertEqual(
                RHVoiceApostropheNormalizer.normalizeText("п\(variant)ятниця"),
                "п'ятниця",
                "Failed to normalize \(variant.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))"
            )
        }
    }

    func testWordsNormalizeToEngineApostrophe() {
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeText("п'ятниця"), "п'ятниця")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeText("п’ятниця"), "п'ятниця")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeText("п&apos;ятниця"), "п'ятниця")
    }

    func testStandaloneApostropheRequestSpeaksApostrophe() {
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("'"), "прямий апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("’"), "правий апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("‘"), "лівий апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("`"), "зворотний апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("&#96;"), "зворотний апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("&#x60;"), "зворотний апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("&grave;"), "зворотний апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("<speak><voice name=\"x\">`</voice></speak>"), "зворотний апостроф")
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("<speak><voice name=\"x\">ʼ</voice></speak>"), "буквений апостроф")
    }

    func testStandaloneApostropheDoesNotRewriteWords() {
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("п'ятниця"))
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneApostropheRequest("<speak>ім'я</speak>"))
    }

    func testSSMLTagsAreNotModified() {
        let ssml = "<speak><tag value=\"п&apos;ятниця\">м'ясо</tag></speak>"

        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(ssml),
            "<speak><tag value=\"п&apos;ятниця\">м'ясо</tag></speak>"
        )
    }

    func testNormalizationIsIdempotent() {
        let normalized = "ім'я об'єкт сім'я"

        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeText(normalized), normalized)
    }

    func testLargeIntegersNormalizeToWordsInTextSegments() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Число 12345 готове."),
            "Число дванадцять тисяч триста сорок п'ять готове."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Число 123456 готове."),
            "Число сто двадцять три тисячі чотириста п'ятдесят шість готове."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Число 1234567 готове."),
            "Число один мільйон двісті тридцять чотири тисячі п'ятсот шістдесят сім готове."
        )
    }

    func testFourDigitYearsAreNotNormalizedAsLargeIntegers() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Рік 2026 готовий."),
            "Рік 2026 готовий."
        )
    }

    func testReportedLargeIntegersNormalizeInsideMarkdownList() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("* 145928\n* 3025471\n* 25896314\n* 104857600\n* 9531847206"),
            "* сто сорок п'ять тисяч дев'ятсот двадцять вісім\n* три мільйони двадцять п'ять тисяч чотириста сімдесят один\n* двадцять п'ять мільйонів вісімсот дев'яносто шість тисяч триста чотирнадцять\n* сто чотири мільйони вісімсот п'ятдесят сім тисяч шістсот\n* дев'ять мільярдів п'ятсот тридцять один мільйон вісімсот сорок сім тисяч двісті шість"
        )
    }

    func testDecimalFractionsNormalizeToUkrainianFractionWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 0,1."),
            "Значення нуль цілих одна десята."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 1,5."),
            "Значення одна ціла п'ять десятих."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 2,08."),
            "Значення дві цілих вісім сотих."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 4,1006."),
            "Значення чотири цілих одна тисяча шість десятитисячних."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 2,000001."),
            "Значення дві цілих одна мільйонна."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 3,1234567."),
            "Значення три цілих один мільйон двісті тридцять чотири тисячі п'ятсот шістдесят сім десятимільйонних."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 4,000000000001."),
            "Значення чотири цілих одна трильйонна."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Значення 124,000005."),
            "Значення сто двадцять чотири цілих п'ять мільйонних."
        )
    }

    func testFullDotDatesNormalizeToUkrainianWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("10.07.2026"),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("01.01.2000"),
            "перше січня двохтисячного року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("31.12.1999"),
            "тридцять перше грудня тисяча дев'ятсот дев'яносто дев'ятого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("23.08.1991"),
            "двадцять третє серпня тисяча дев'ятсот дев'яносто першого року"
        )
    }

    func testFullDotDatesNormalizeInsideSentencesAndSayAs() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Звіт здано 05.07.2026 вчасно."),
            "Звіт здано п'яте липня дві тисячі двадцять шостого року вчасно."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дата 10.07.2026."),
            "Дата десяте липня дві тисячі двадцять шостого року."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">10.07.2026</say-as>"#),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="date">10.07.2026</say-as>"#),
            #"<say-as interpret-as="date">десяте липня дві тисячі двадцять шостого року</say-as>"#
        )
    }

    func testFullDotDatesSplitBySayAsTagsNormalizeToUkrainianWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"10.07.<say-as interpret-as="telephone">2026</say-as>"#),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">10</say-as>.<say-as interpret-as="telephone">07</say-as>.<say-as interpret-as="telephone">2026</say-as>"#),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<speak>Звіт здано 05.07.<say-as interpret-as="telephone">2026</say-as> вчасно.</speak>"#),
            "<speak>Звіт здано п'яте липня дві тисячі двадцять шостого року вчасно.</speak>"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<speak>Звіт здано 10.07.<say-as interpret-as="telephone">2026</say-as>.</speak>"#),
            "<speak>Звіт здано десяте липня дві тисячі двадцять шостого року.</speak>"
        )
    }

    func testFullDotDatesSplitBySayAsTagsWithExtraAttributesNormalize() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"10.07.<say-as interpret-as="telephone" format="digits">2026</say-as>"#),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"10.07.<say-as format="digits" interpret-as="characters"> 2026 </say-as>"#),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="number" detail="2">10</say-as>.<say-as interpret-as="number" detail="2">07</say-as>.<say-as interpret-as="number" detail="4">2026</say-as>"#),
            "десяте липня дві тисячі двадцять шостого року"
        )
    }

    func testVerbalizedDotDatesFromIOS26NormalizeToUkrainianWords() {
        // iOS 26 VoiceOver замінює крапки словом «крапка» ще до синтезатора
        // (доведено логом пристрою 2026-07-21).
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("10 крапка 07 крапка 2026"),
            "десяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Звіт здано 05 крапка 07 крапка 2026 вчасно."),
            "Звіт здано п'яте липня дві тисячі двадцять шостого року вчасно."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("01 крапка 01 крапка 2000"),
            "перше січня двохтисячного року"
        )
    }

    func testVerbalizedDotNonDatesStayUntouched() {
        // День 32 — невалідний: числа лишаються числами.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дата 32 крапка 07 крапка 2026."),
            "Дата 32 крапка 07 крапка 2026."
        )
        // Місяць 13 — невалідний.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("10 крапка 13 крапка 2026"),
            "10 крапка 13 крапка 2026"
        )
        // Версія «1 крапка 16.4»: лише одна «крапка» — датний шаблон не збігається,
        // рядок лишається без змін.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Версія 1 крапка 16.4."),
            "Версія 1 крапка 16.4."
        )
    }

    func testWeekdayAbbreviationsWithDatesNormalize() {
        // Формати з багрепорту Даші (build 187): пт, 17.07.2026 / пт 17.07.2026 / пт17.07.2026 / Нд19.07.2026
        let friday = "п'ятниця, сімнадцяте липня дві тисячі двадцять шостого року"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeInTextSegments("пт, 17.07.2026"), friday)
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeInTextSegments("пт 17.07.2026"), friday)
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeInTextSegments("пт17.07.2026"), friday)
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Нд19.07.2026"),
            "неділя, дев'ятнадцяте липня дві тисячі двадцять шостого року"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Вт23.06.2026"),
            "вівторок, двадцять третє червня дві тисячі двадцять шостого року"
        )
        // Та сама дата з озвученими крапками (iOS 26).
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("пт, 17 крапка 07 крапка 2026"),
            friday
        )
        // Невалідна дата: день тижня і числа лишаються як є.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("пт 32.07.2026"),
            "пт 32.07.2026"
        )
    }

    func testPlainTextPlusPhoneNumbersReadDigitByDigitInGroups() {
        // Баг Даші (build 187): суцільний +380… читався мільйонами.
        // Групування суцільного номера — за форматом Андрія: +38 067 344 91 61.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон +380673449161.", phoneReadingMode: .digits),
            "Телефон плюс три вісім, нуль шість сім, три чотири чотири, дев'ять один, шість один."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон +38 067 344 91 61.", phoneReadingMode: .digits),
            "Телефон плюс три вісім, нуль шість сім, три чотири чотири, дев'ять один, шість один."
        )
    }

    func testDatesAsWordsToggleOffKeepsDatesAsDigits() {
        // Перемикач «Читати дати словами» ВИМКНЕНО — дати лишаються цифрами.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("10.07.2026", datesAsWords: false),
            "10.07.2026"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Звіт здано 05 крапка 07 крапка 2026 вчасно.", datesAsWords: false),
            "Звіт здано 05 крапка 07 крапка 2026 вчасно."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("пт, 17.07.2026", datesAsWords: false),
            "пт, 17.07.2026"
        )
        // Телефони працюють НЕЗАЛЕЖНО від перемикача дат.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон +38 067 344 91 61.", datesAsWords: false, phoneReadingMode: .digits),
            "Телефон плюс три вісім, нуль шість сім, три чотири чотири, дев'ять один, шість один."
        )
    }

    func testInvalidDatesAndVersionsAreNotNormalized() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дата 32.07.2026."),
            "Дата 32.07.2026."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дата 10.13.2026."),
            "Дата 10.13.2026."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дата 10.07.20261."),
            "Дата 10.07.20261."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Версія 1.16.4 і 1.18."),
            "Версія 1.16.4 і 1.18."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"Дата 32.07.<say-as interpret-as="telephone">2026</say-as>."#),
            "Дата 32.07.дві тисячі двадцять шість."
        )
    }

    func testTelephoneSayAsShortBlocksNormalizeAsNumbers() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">124685</say-as>"#),
            "сто двадцять чотири тисячі шістсот вісімдесят п'ять"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">1234567</say-as>"#),
            "один мільйон двісті тридцять чотири тисячі п'ятсот шістдесят сім"
        )
    }

    func testTelephoneSayAsSplitDecimalNormalizesAsFraction() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"Значення 0,<say-as interpret-as="telephone">365476</say-as>."#),
            "Значення нуль цілих триста шістдесят п'ять тисяч чотириста сімдесят шість мільйонних."
        )
    }

    func testTelephoneSayAsPhoneNumbersNormalizeDigitByDigit() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">+380501234567</say-as>"#, phoneReadingMode: .digits),
            "плюс три вісім, нуль п'ять нуль, один два три, чотири п'ять, шість сім"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">+380 50 123 45 67</say-as>"#, phoneReadingMode: .digits),
            "плюс три вісім нуль, п'ять нуль, один два три, чотири п'ять, шість сім"
        )
    }

    func testTelephoneSayAsDistinguishesGroupedMoneyFromPhones() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">30 018</say-as>"#),
            "тридцять тисяч вісімнадцять"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">10 000</say-as>"#),
            "десять тисяч"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">3 050</say-as>"#),
            "три тисячі п'ятдесят"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">30 018,00</say-as>"#),
            "тридцять тисяч вісімнадцять гривень нуль копійок"
        )
    }

    func testTelephoneSayAsUsesGroupsByDefaultAndDigitsOnRequest() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">067 344 91 61</say-as>"#),
            "нуль шістдесят сім, триста сорок чотири, дев'яносто один, шістдесят один"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">0 800 500 500</say-as>"#),
            "нуль, вісімсот, п'ятсот, п'ятсот"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">+380 97 148 98 92</say-as>"#),
            "плюс триста вісімдесят, дев'яносто сім, сто сорок вісім, дев'яносто вісім, дев'яносто два"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">1234 5678 9012 3456</say-as>"#),
            "одна тисяча двісті тридцять чотири, п'ять тисяч шістсот сімдесят вісім, дев'ять тисяч дванадцять, три тисячі чотириста п'ятдесят шість"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">453449161</say-as>"#),
            "чотириста п'ятдесят три мільйони чотириста сорок дев'ять тисяч сто шістдесят один"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">+380 97 148 98 92</say-as>"#, phoneReadingMode: .digits),
            "плюс три вісім нуль, дев'ять сім, один чотири вісім, дев'ять вісім, дев'ять два"
        )
    }

    func testTelephoneSayAsDoesNotTreatArithmeticPlusAsPhonePrefix() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">10+ 453449161</say-as>"#),
            "10+ чотириста п'ятдесят три мільйони чотириста сорок дев'ять тисяч сто шістдесят один"
        )
    }

    func testPhoneProcessingToggleLeavesTelephoneSayAsToSystem() {
        let input = #"<say-as interpret-as="telephone">+380 97 148 98 92</say-as>"#
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(input, phoneProcessing: false),
            input
        )
    }

    func testSlashBetweenNumbersIsSpokenAsDrib() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дроби 3/5, 9/10, 15/32."),
            "Дроби три дріб п'ять, дев'ять дріб десять, п'ятнадцять дріб тридцять два."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Половина 1/2 і третина 1/3."),
            "Половина один дріб два і третина один дріб три."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Сторінка 100/200."),
            "Сторінка сто дріб двісті."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дата 3/11."),
            "Дата три дріб одинадцять."
        )
    }

    func testMixedSlashFractionsNormalizeToUkrainianFractionWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Мішані: 2 цілих 4/7; 10 цілих 11/12; 154 цілих 1/3."),
            "Мішані: дві цілих чотири сьомих; десять цілих одинадцять дванадцятих; сто п'ятдесят чотири цілих одна третя."
        )
    }

    // MARK: - build 190, фікс 1: скорочені текстові місяці (екран блокування)

    func testAbbreviatedTextMonthDatesNormalizeToUkrainianWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("чт 23 лип."),
            "четвер, двадцять третє липня"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("23 лип."),
            "двадцять третє липня"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("чт, 23 лип."),
            "четвер, двадцять третє липня"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("23 лип. 2026"),
            "двадцять третє липня дві тисячі двадцять шостого року"
        )
        // Повна назва місяця в родовому відмінку теж приймається.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("23 липня 2026"),
            "двадцять третє липня дві тисячі двадцять шостого року"
        )
        // Невалідний день — не чіпати.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("32 лип."),
            "32 лип."
        )
        // Перемикач «Читати дати словами» вимкнено — лишається як є.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("чт 23 лип.", datesAsWords: false),
            "чт 23 лип."
        )
    }

    // MARK: - build 190, фікс 2: час ГГ:ХХ словами

    func testTimeHHMMNormalizesToUkrainianWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("17:01"),
            "сімнадцята година одна хвилина"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("09:00"),
            "дев'ята година рівно"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("17:05"),
            "сімнадцята година п'ять хвилин"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("00:22"),
            "нульова година двадцять дві хвилини"
        )
    }

    func testTimeLikeRatiosWithNonTwoDigitMinutesAreNotTouched() {
        // «3:1» — рахунок, а не час: хвилини мають бути рівно 2 цифри.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Рахунок 3:1."),
            "Рахунок 3:1."
        )
    }

    func testUkrainianTimeUnitAbbreviationsExpandWithGrammar() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Залишилася 1 хв. Ще 2 год і 30 сек."),
            "Залишилася одна хвилина. Ще дві години і тридцять секунд."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("5 хв", abbreviationsAsWords: false),
            "5 хв"
        )
    }

    // MARK: - build 190, фікс 3: латинські абревіатури по буквах

    func testLatinAllCapsAbbreviationsWrapInCharacterSayAs() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Увімкни VPN."),
            #"Увімкни <say-as interpret-as="characters">VPN</say-as>."#
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Мережа LTE недоступна."),
            #"Мережа <say-as interpret-as="characters">LTE</say-as> недоступна."#
        )
    }

    func testRomanNumeralsAreNotWrappedAsLatinAbbreviations() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Розділ III готовий."),
            "Розділ III готовий."
        )
    }

    func testLatinAbbreviationsWithDigitsAreNotTouched() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Стандарт 4G і iOS26 тут."),
            "Стандарт 4G і iOS26 тут."
        )
    }

    // MARK: - build 197: never invent a missing phone prefix

    func testPhoneNumbersStartingWith380KeepOnlyExplicitPlus() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон 380671234567."),
            "Телефон тридцять вісім, нуль шістдесят сім, сто двадцять три, сорок п'ять, шістдесят сім."
        )
        // Явний плюс вимовляється рівно один раз.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон +380671234567."),
            "Телефон плюс тридцять вісім, нуль шістдесят сім, сто двадцять три, сорок п'ять, шістдесят сім."
        )
        // Навіть некоректно подвоєний знак не створює два «плюс» у вимові.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон ++380671234567."),
            "Телефон плюс тридцять вісім, нуль шістдесят сім, сто двадцять три, сорок п'ять, шістдесят сім."
        )
    }
}
