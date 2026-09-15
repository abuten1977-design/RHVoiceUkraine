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
            "тридцять тисяч вісімнадцять"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">30 018,50</say-as>"#),
            "тридцять тисяч вісімнадцять цілих п'ятдесят сотих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">1 234,05</say-as>"#),
            "одна тисяча двісті тридцять чотири цілих п'ять сотих"
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
            "один два три чотири, п'ять шість сім вісім, дев'ять нуль один два, три чотири п'ять шість"
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
        // Арифметичний плюс не робить число телефоном. Раніше «+» лишався
        // сирим і рушій його мовчки пропускав (аудит Даші, збірка 206, п.15) —
        // тепер він вимовляється словом «плюс».
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(#"<say-as interpret-as="telephone">10+ 453449161</say-as>"#),
            "10 плюс чотириста п'ятдесят три мільйони чотириста сорок дев'ять тисяч сто шістдесят один"
        )
    }

    func testPlainTextGroupedAmountsAndPhonesUseSharedClassification() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("На рахунку 30 118,90"),
            "На рахунку тридцять тисяч сто вісімнадцять цілих дев'яносто сотих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("На рахунку 30 118.90"),
            "На рахунку тридцять тисяч сто вісімнадцять цілих дев'яносто сотих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Зараховано +9 000.00"),
            "Зараховано плюс дев'ять тисяч"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Зняття -17 000"),
            "Зняття мінус сімнадцять тисяч"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("40 000, 3 050, 1 234 567"),
            "сорок тисяч, три тисячі п'ятдесят, один мільйон двісті тридцять чотири тисячі п'ятсот шістдесят сім"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("40\u{00A0}000"),
            "сорок тисяч"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Телефон +380 97 148 98 92"),
            "Телефон плюс триста вісімдесят, дев'яносто сім, сто сорок вісім, дев'яносто вісім, дев'яносто два"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("067 344 91 61"),
            "нуль шістдесят сім, триста сорок чотири, дев'яносто один, шістдесят один"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("17.07.2026"),
            "сімнадцяте липня дві тисячі двадцять шостого року"
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
            "Увімкни ве пе ен."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Мережа LTE недоступна."),
            "Мережа ел те е недоступна."
        )
    }

    // Раніше римські числа лишалися сирими, і рушій читав «III» як «айіі»
    // (аудит Даші, збірка 206, п.29) — тепер вони стають числівниками.
    func testRomanNumeralsAreSpokenAsNumbers() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Розділ III готовий."),
            "Розділ три готовий."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Століття XIV"),
            "Століття чотирнадцять"
        )
        // Некоректний набір римських літер не «читаємо» і не диктуємо по буквах.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Код VVX тут."),
            "Код VVX тут."
        )
    }

    func testLatinAbbreviationsWithDigitsAreNotTouched() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Стандарт 4G і iOS26 тут."),
            "Стандарт 4G і iOS26 тут."
        )
    }

    // MARK: - build 205: abbreviation replacement dictionary

    func testAbbreviationDictionaryExpandsWholeWordsAfterStructuredValues() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("ср. вт, LTE VPN"),
            "середа. вівторок, ел те е ве пе ен"
        )
        // This textual date was already consumed by the date pass before the
        // dictionary sees the short month token.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("23 лип."),
            "двадцять третє липня"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("vpnclient LTE"),
            "vpnclient ел те е"
        )
    }

    func testAbbreviationDictionaryUserEntryOverridesBundledEntry() {
        let entries = AbbreviationDictionary.mergedEntries(userEntries: [
            AbbreviationDictionaryEntry(abbreviation: "ср", replacement: "середа користувача")
        ])
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("ср", abbreviationDictionaryEntries: entries),
            "середа користувача"
        )
    }

    func testAbbreviationDictionaryUsesNaturalUkrainianWiFiPronunciation() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Підключено Wi-Fi"),
            "Підключено вай-фай"
        )
    }

    func testAbbreviationDictionaryCanBeDisabled() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("ср LTE", abbreviationDictionaryEnabled: false),
            #"ср <say-as interpret-as="characters">LTE</say-as>"#
        )
    }

    func testUnreadableAbbreviationDictionaryFallsBackToBundledEntries() {
        XCTAssertEqual(AbbreviationDictionary.entries(from: Data([0xFF])), .failure(.unreadableFile))
        XCTAssertTrue(AbbreviationDictionary.mergedEntries(userEntries: []).contains {
            $0.abbreviation == "ср" && $0.replacement == "середа"
        })
    }

    func testAbbreviationDictionaryExportAndImportDoNotDuplicateEntries() throws {
        let original = [
            AbbreviationDictionaryEntry(abbreviation: "БПЛА", replacement: "безпілотний літальний апарат"),
            AbbreviationDictionaryEntry(abbreviation: "ОСББ", replacement: "об'єднання співвласників")
        ]
        let url = try AbbreviationDictionary.makeExportFile(entries: original, now: Date(timeIntervalSince1970: 0))
        defer { try? FileManager.default.removeItem(at: url) }
        let preview = try AbbreviationDictionary.importPreview(from: Data(contentsOf: url)).get()
        let result = AbbreviationDictionary.applyImport(preview, to: original, mode: .add)
        XCTAssertEqual(result.entries, original)
        XCTAssertEqual(result.summary.added, 0)
        XCTAssertEqual(result.summary.updated, 2)
    }

    func testAbbreviationDictionaryImportAddUpdatesAndReplaceRemovesOldEntries() {
        let existing = [
            AbbreviationDictionaryEntry(abbreviation: "БПЛА", replacement: "старе"),
            AbbreviationDictionaryEntry(abbreviation: "ОСББ", replacement: "старе ОСББ")
        ]
        let preview = AbbreviationDictionaryImportPreview(entries: [
            AbbreviationDictionaryEntry(abbreviation: "БПЛА", replacement: "нове"),
            AbbreviationDictionaryEntry(abbreviation: "ЄС", replacement: "Європейський Союз")
        ], skippedLines: 0)
        let added = AbbreviationDictionary.applyImport(preview, to: existing, mode: .add)
        XCTAssertEqual(added.entries.count, 3)
        XCTAssertEqual(added.summary, AbbreviationDictionaryImportSummary(added: 1, updated: 1, skipped: 0))
        XCTAssertTrue(added.entries.contains { $0.abbreviation == "ОСББ" })

        let replaced = AbbreviationDictionary.applyImport(preview, to: existing, mode: .replace)
        XCTAssertEqual(replaced.entries, preview.entries)
        XCTAssertEqual(replaced.summary, AbbreviationDictionaryImportSummary(added: 2, updated: 0, skipped: 0))
    }

    func testAbbreviationDictionaryImportCountsBadLinesAndRejectsEmptyFile() {
        let data = Data("БПЛА = безпілотний\nнекоректний\n= порожній ключ\nЄС = \nЄС => Європейський Союз\n".utf8)
        let preview = try? AbbreviationDictionary.importPreview(from: data).get()
        XCTAssertEqual(preview?.entries.count, 2)
        XCTAssertEqual(preview?.skippedLines, 3)
        if case let .failure(error) = AbbreviationDictionary.importPreview(from: Data()) {
            XCTAssertEqual(error, .emptyImport)
        } else {
            XCTFail("Порожній файл має бути відхилений")
        }
    }

    func testAbbreviationDictionaryMatcherKeepsTypingPathFastWithHundredEntries() {
        let entries = (0..<100).map {
            AbbreviationDictionaryEntry(abbreviation: "ТЕСТ\($0)", replacement: "заміна \($0)")
        }
        let matcher = AbbreviationDictionaryMatcher(entries: entries)
        let start = Date()
        for _ in 0..<1_000 {
            XCTAssertEqual(matcher.replace(in: "а") { _, _, _ in true }, "а")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25, "Один символ не повинен будувати регулярні вирази словника")
    }

    func testAbbreviationDictionaryLongerKeyWinsOverShorterKey() {
        let entries = [
            AbbreviationDictionaryEntry(abbreviation: "USB", replacement: "коротке"),
            AbbreviationDictionaryEntry(abbreviation: "USB-C", replacement: "довге")
        ]
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("USB-C", abbreviationDictionaryEntries: entries),
            "довге"
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

    // MARK: - Фікси за аудитом Даші (збірка 206, 01.08.2026)

    func testStandalonePlusBeforeNumberIsSpoken() {
        // Пункт 15: «Зараховано +9 000.00» — плюс губився.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Зараховано +9 000.00"),
            "Зараховано плюс дев'ять тисяч"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("2+2"),
            "2 плюс 2"
        )
    }

    func testMinusBeforeAmountIsSpoken() {
        // Пункт 16: «Зняття -17 000» — мінус мовчав.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Зняття -17 000"),
            "Зняття мінус сімнадцять тисяч"
        )
        // Юнікодний мінус U+2212 і коротке тире — та сама вимова.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Зняття \u{2212}17 000"),
            "Зняття мінус сімнадцять тисяч"
        )
        // Діапазон не є мінусом: перед знаком стоїть цифра.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("10-15"),
            "10-15"
        )
    }

    func testPercentSignsAreSpoken() {
        // Пункт 28: знак відсотка не відтворювався.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("15%"),
            "15 відсотків"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("1%"),
            "1 відсоток"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("22%"),
            "22 відсотки"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("2,5%"),
            "дві цілих п'ять десятих відсотка"
        )
    }

    func testDottedGroupedAmountReadsAsDecimal() {
        // Пункт 14: сума «30 118.90» з крапкою розвалювалась на два числа.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("30 118.90"),
            "тридцять тисяч сто вісімнадцять цілих дев'яносто сотих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("30 118,90"),
            "тридцять тисяч сто вісімнадцять цілих дев'яносто сотих"
        )
    }

    func testVerbalizedDotAmountsFromIOS() {
        // iOS проговорює крапку словом ще до синтезатора (доведено для дат
        // логом 2026-07-21) — суми приходять як «30 118 крапка 90».
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("30 118 крапка 90"),
            "тридцять тисяч сто вісімнадцять цілих дев'яносто сотих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Зараховано +9 000 крапка 00"),
            "Зараховано плюс дев'ять тисяч"
        )
        // Версії не чіпаємо: без тисячного розділювача правило не діє.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Версія 1 крапка 18"),
            "Версія 1 крапка 18"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("1 крапка 16 крапка 4"),
            "1 крапка 16 крапка 4"
        )
    }

    func testVulgarFractionSymbolsAreSpoken() {
        // Пункт 27: «Нотатки» автозаміною перетворюють 1/2 на «½»,
        // і коса риска «зникала».
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("½"),
            "одна друга"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("¾"),
            "три четвертих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("1½"),
            "1 і одна друга"
        )
    }

    func testAsciiSimpleFractionsStillWork() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("1/2, 3/4"),
            "один дріб два, три дріб чотири"
        )
    }

    func testBareSecondsExpandOnlyInClockContext() {
        // Пункти 22–23: «01 год 15 хв 5 с» — голе «с» лишалося нерозгорнутим.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("01 год 15 хв 5 с"),
            "одна година п'ятнадцять хвилин п'ять секунд"
        )
        // Без «хв»/«год» поруч «с.» може бути «село» чи «сторінка» — не чіпаємо.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Їхали через 5 с. Іванівка"),
            "Їхали через 5 с. Іванівка"
        )
    }

    func testWiFiBundledDictionaryEntryApplies() {
        // Пункт 24 аудиту: Wi-Fi має читатися «вай-фай» через базовий словник.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments(
                "Мережа Wi-Fi активна",
                abbreviationDictionaryEntries: AbbreviationDictionary.bundledEntries
            ),
            "Мережа вай-фай активна"
        )
    }

    // MARK: - Стражі після критика (18.08.2026)

    func testVerbalizedDotAmountWithNarrowNoBreakSpace() {
        // Банки і iOS групують розряди нерозривними пробілами (U+202F, U+00A0):
        // саме ця форма приходить із Приват24, а не ASCII-пробіл.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("30\u{202F}118 крапка 90"),
            "тридцять тисяч сто вісімнадцять цілих дев'яносто сотих"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("9\u{00A0}000 крапка 00"),
            "дев'ять тисяч"
        )
    }

    func testDashBeforePriceIsNotMinus() {
        // Тире-зв'язка перед сумою — НЕ від'ємне число: знак мінуса мусить
        // прилягати до цифри.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Ціна — 250 грн"),
            "Ціна — 250 гривні"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("10 - 15 хвилин"),
            "10 - 15 хвилин"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("- 5 пунктів"),
            "- 5 пунктів"
        )
    }

    func testRomanLookalikeAbbreviationsStayUntouched() {
        // XL, CV, CD — формально римські числа, але в житті це розмір одягу,
        // резюме і диск. Лишаємо сирими, як було.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Розмір XL підійшов."),
            "Розмір XL підійшов."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Надішліть CV сюди."),
            "Надішліть CV сюди."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Диск CD старий."),
            "Диск CD старий."
        )
    }

    // --- Форми, у яких iOS вiддає знак СЛОВОМ (замiр 24.08.2026) ---
    // При увiмкненiй деталiзацiї пунктуацiї система пiдставляє слово замiсть знака:
    // «%» → «вiдсоток» (ЗАВЖДИ однина), «:» → «двокрапка». Правила мусять розумiти
    // обидвi форми, бо налаштування користувача ми не контролюємо i виміряти
    // на чужих пристроях не можемо.

    func testVerbalizedPercentGetsCorrectNounForm() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("15 відсоток"),
            "15 відсотків"
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("22 відсоток"),
            "22 відсотки"
        )
        // Число, для якого однина ВIРНА — рядок не змiнюється.
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("1 відсоток"),
            "1 відсоток"
        )
    }

    func testVerbalizedPercentDoesNotTouchAdjectives() {
        // «вiдсотковий» — не одиниця вимiру, чiпати не можна.
        let input = "5 відсоткових пунктів"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeInTextSegments(input), input)
    }

    func testVerbalizedColonReadsAsTime() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("14 двокрапка 30"),
            "чотирнадцята година тридцять хвилин"
        )
    }

    func testVerbalizedColonDoesNotTurnScoreIntoTime() {
        // Рахунок «3 двокрапка 1»: хвилини мусять бути РIВНО двi цифри,
        // тому це НЕ час i чiпати його не можна.
        let input = "3 двокрапка 1"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeInTextSegments(input), input)
    }


    // MARK: - Letter «і» announced by its Unicode name (measured 2026-09-06)

    func testMeasuredLetterINameRequestBecomesTheLetterItself() {
        // Рядок ЗНЯТИЙ з живого iPhone 12 / iOS 26.6.1, збірка 226, журнал
        // cap26_2026-09-06.txt. Остання буква у назві — ЛАТИНСЬКА i (U+0069),
        // саме через неї Андрій чув «ай» у кінці фрази.
        let measured = "<speak><lang xml:lang=\"uk\"><prosody rate=\"400.0%\"> білорусько-українська \u{0069} </prosody></lang></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(measured), "і")
    }

    func testLetterINameIsNormalizedRegardlessOfLetterVariantAndWordOrder() {
        let variants = [
            "білорусько-українська \u{0069}",
            "білорусько-українська \u{0456}",
            "українсько-білоруська \u{0069}",
            "українсько-білоруська \u{0456}",
            "  Білорусько-Українська   \u{0069}  "
        ]
        for variant in variants {
            XCTAssertEqual(
                RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(variant),
                "і",
                "не спрацювало на варіанті: \(variant)"
            )
        }
    }

    func testOtherLettersAreLeftAloneByDecision() {
        // ВАЖЛИВО, чому саме NIL. Правило чіпає лише цілі запити-назви букв, що
        // збігаються з таблицею (зараз «і» і «є»). Звичайний текст із самими
        // буквами не є такою назвою і має лишатися недоторканим.
        for text in ["<speak>Їжак</speak>", "<speak>Євген</speak>", "<speak>ї</speak>", "<speak>є</speak>"] {
            XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(text))
        }
    }

    // MARK: - Letter «є» announced by iOS's wrong letter name (measured 2026-09-06)

    func testMeasuredLetterENameRequestBecomesTheLetterItself() {
        // Рядок ЗНЯТИЙ з живого iPhone / iOS, журнал cap26_2026-09-06.txt: при
        // читанні по буквах «є» iOS називає ЧУЖУ кириличну літеру «ї»
        // (U+0457), через що замість «йе» чується «йи».
        let measured = "<speak><lang xml:lang=\"uk\"><prosody rate=\"400.0%\"> українська ї </prosody></lang></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(measured), "є")
    }

    func testLetterENameIsNormalizedRegardlessOfWordingAndWordOrder() {
        // «українська ї» — виміряна форма. «українська є» — правильне
        // формулювання, на випадок якщо Apple виправить свою локалізацію.
        // Обидва порядки слів покриті так само, як і для «і» вище.
        let variants = [
            "українська ї",
            "ї українська",
            "українська є",
            "є українська",
            "  Українська   Ї  "
        ]
        for variant in variants {
            XCTAssertEqual(
                RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(variant),
                "є",
                "не спрацювало на варіанті: \(variant)"
            )
        }
    }

    func testRealLetterYiRequestIsNotTouched() {
        // Справжня буква «ї» приходить як « yi » (дві ЛАТИНСЬКІ літери) і вже
        // звучить правильно — цього правила вона торкатися не повинна.
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(" yi "))
    }

    func testOrdinaryTextWithLetterEWordsIsNotReplaced() {
        // Сторож: слова «українська» і «ї» посеред звичайного речення не є
        // цілим запитом-назвою букви і не повинні замінюватися.
        let ordinary = [
            "це українська ї та ще щось",
            "Мова українська, ї не єдина буква"
        ]
        for text in ordinary {
            XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(text))
        }
    }

    func testInvisibleFormattingCharactersDoNotDefeatTheLetterERule() {
        let withLRM = "\u{200E} українська ї\u{200E} "
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(withLRM), "є")
    }

    func testTrailingPunctuationDoesNotDefeatTheLetterERule() {
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest("українська ї."), "є")
    }

    // MARK: - Letter «ґ» announced by its Unicode name (measured 2026-09-14)

    func testMeasuredSmallGheWithUpturnNameRequestBecomesTheLetterItself() {
        // Рядок ЗНЯТИЙ з живого iPhone 12 / iOS 26.6.1, збірка 230, журнал
        // /tmp/cap_g_2026-09-14_0957.txt. iOS шле не саму літеру, а її
        // юнікодну назву, перекладену наполовину: латинське «ghe» + «піднесення».
        // Андрій незалежно підтвердив на слух: чув «г піднесення».
        let measured = "<speak><lang xml:lang=\"uk\"><prosody pitch=\"-10.000004%\" rate=\"190.00002%\"> ghe, піднесення </prosody></lang></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(measured), "ґ")
    }

    func testGheNameIsNormalizedRegardlessOfCommaAndWordOrder() {
        let variants = [
            "ghe, піднесення",
            "ghe піднесення",
            "піднесення, ghe",
            "піднесення ghe",
            "ге, піднесення",
            "  GHE,   Піднесення  "
        ]
        for variant in variants {
            XCTAssertEqual(
                RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(variant),
                "ґ",
                "не спрацювало на варіанті: \(variant)"
            )
        }
    }

    func testCapitalGheArrivesCorrectlyAndIsLeftAlone() {
        // ⭐ВЕЛИКА «Ґ» НЕ ЗЛАМАНА: iOS шле «Велика» плюс СПРАВЖНЮ літеру в тезі
        // посимвольного читання. Андрій підтвердив на слух 14.09, що вона звучить
        // правильно. Правило не повинно її чіпати — інакше ми зламаємо робоче.
        let capital = "<speak><lang xml:lang=\"uk\">Велика <say-as interpret-as=\"characters\">ґ</say-as></lang></speak>"
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(capital))
    }

    func testOrdinaryUkrainianTextWithTheWordPidnesennyaIsNotReplaced() {
        // Сторож: «піднесення» — звичайне українське слово. Правило має ловити
        // лише цілий запит-назву букви, а не будь-яку згадку слова.
        let ordinary = [
            "піднесення духу",
            "економічне піднесення країни",
            "це піднесення, а не спад"
        ]
        for text in ordinary {
            XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(text))
        }
    }

    func testWordsContainingGheAreNotTouched() {
        // Слова з «ґ» усередині Андрій 14.09 почув правильно — суцільне читання
        // не ламається. Правило не повинно в них лізти.
        for text in ["<speak>ґанок,</speak>", "<speak>ґудзик,</speak>", "<speak>ґрунт</speak>", "<speak>дзиґа</speak>"] {
            XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(text))
        }
    }

    func testInvisibleFormattingCharactersDoNotDefeatTheRule() {
        // U+200E (LRM) реально трапляється всередині рядків VoiceOver на iOS 27.
        // Він не належить до пробільних, тож без окремого зняття правило б
        // мовчки промахнулося.
        let withLRM = "\u{200E} білорусько-українська \u{0069}\u{200E} "
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(withLRM), "і")
    }

    func testTrailingPunctuationDoesNotDefeatTheRule() {
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest("білорусько-українська \u{0069}."), "і")
    }

    func testOrdinaryTextWithTheSameWordsIsNotReplaced() {
        // Сторож: правило спрацьовує ЛИШЕ на цілому запиті, що складається саме
        // з назви букви, і не чіпає звичайну мову.
        let ordinary = [
            "білорусько-українська співпраця",
            "це білорусько-українська i ще щось",
            "Мова білорусько-українська"
        ]
        for text in ordinary {
            XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(text))
        }
    }

    func testEmptyRequestIsNotTouched() {
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest("<speak></speak>"))
    }

    // MARK: - iOS 26 vs iOS 27 letter-name shapes (measured 2026-09-08)
    //
    // iOS 26 sends the letter-name phrase as ONE text run — see
    // ~/aiwork/copilot/cap_letters_2026-09-08_ios26.txt. iOS 27 sends the SAME
    // phrase as THREE separate `<s>` sentences (name, pause, alphabet word) —
    // see ~/rhvoice/cap27_letters_2026-09-08.txt (Mac, ssh andrey@10.164.231.25).
    // Both forms below are copied verbatim from those captures.

    func testIOS26CaptureLetterINameBecomesTheLetterItself() {
        // Verbatim from cap_letters_2026-09-08_ios26.txt (single text run) —
        // old join-then-compare behaviour must not change for this shape.
        let ios26 = "<speak><lang xml:lang=\"uk\"><prosody pitch=\"-10.000004%\" rate=\"190.00002%\"> білорусько-українська i </prosody></lang></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(ios26), "і")
    }

    func testIOS26CaptureLetterENameBecomesTheLetterItself() {
        // Verbatim from cap_letters_2026-09-08_ios26.txt (single text run).
        let ios26 = "<speak><lang xml:lang=\"uk\"><prosody pitch=\"-10.000004%\" rate=\"190.00002%\"> українська ї </prosody></lang></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(ios26), "є")
    }

    func testIOS27CaptureLetterINameRewritesOnlyTheMatchingSentence() {
        // Verbatim from cap27_letters_2026-09-08.txt: three separate <s>
        // sentences (name, pause, alphabet word "Іван"). Only the first
        // sentence's text is replaced; the pause and "Іван" stay untouched.
        let ios27 = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\"> білорусько-українська i </lang></s><s><break time=\"750.0ms\"/></s><s><lang xml:lang=\"uk-UA\">Іван</lang></s></prosody></speak>"
        let expected = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\">і</lang></s><s><break time=\"750.0ms\"/></s><s><lang xml:lang=\"uk-UA\">Іван</lang></s></prosody></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(ios27), expected)
    }

    func testIOS27CaptureLetterENameRewritesOnlyTheMatchingSentence() {
        // Verbatim from cap27_letters_2026-09-08.txt, alphabet word "Євген".
        let ios27 = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\"> українська ї </lang></s><s><break time=\"750.0ms\"/></s><s><lang xml:lang=\"uk-UA\">Євген</lang></s></prosody></speak>"
        let expected = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\">є</lang></s><s><break time=\"750.0ms\"/></s><s><lang xml:lang=\"uk-UA\">Євген</lang></s></prosody></speak>"
        XCTAssertEqual(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(ios27), expected)
    }

    func testIOS27CaptureRealLetterYiIsNotTouched() {
        // Verbatim from cap27_letters_2026-09-08.txt: the real «ї» arrives as
        // « yi » (two Latin letters), already sounds correct, and « yi » is
        // not a dictionary key — neither this sentence nor "Їжак" matches, so
        // the whole request must come back nil, unmodified.
        let ios27 = "<speak><prosody rate=\"219.99995%\"><s><lang xml:lang=\"uk-UA\"> yi </lang></s><s><break time=\"750.0ms\"/></s><s><lang xml:lang=\"uk-UA\">Їжак</lang></s></prosody></speak>"
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(ios27))
    }

    func testIOS27StyleMultiSentenceOrdinarySpeechIsNotTouched() {
        // A multi-<s> request that is NOT a letter-name announcement (no
        // sentence text matches the dictionary) must come back nil untouched,
        // the same as any other ordinary text passed through this rule.
        let ordinary = "<speak><prosody rate=\"100%\"><s><lang xml:lang=\"uk-UA\">Привіт</lang></s><s><lang xml:lang=\"uk-UA\">Як справи</lang></s></prosody></speak>"
        XCTAssertNil(RHVoiceApostropheNormalizer.normalizeStandaloneLetterNameRequest(ordinary))
    }

}
