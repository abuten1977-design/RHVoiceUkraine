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
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Число 123456 готове."),
            "Число сто двадцять три тисячі чотириста п'ятдесят шість готове."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Число 1234567 готове."),
            "Число один мільйон двісті тридцять чотири тисячі п'ятсот шістдесят сім готове."
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

    func testSlashFractionsNormalizeToUkrainianFractionWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Дроби 3/5, 9/10, 15/32."),
            "Дроби три п'ятих, дев'ять десятих, п'ятнадцять тридцять других."
        )
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Половина 1/2 і третина 1/3."),
            "Половина одна друга і третина одна третя."
        )
    }

    func testMixedSlashFractionsNormalizeToUkrainianFractionWords() {
        XCTAssertEqual(
            RHVoiceApostropheNormalizer.normalizeInTextSegments("Мішані: 2 цілих 4/7; 10 цілих 11/12; 154 цілих 1/3."),
            "Мішані: дві цілих чотири сьомих; десять цілих одинадцять дванадцятих; сто п'ятдесят чотири цілих одна третя."
        )
    }
}
