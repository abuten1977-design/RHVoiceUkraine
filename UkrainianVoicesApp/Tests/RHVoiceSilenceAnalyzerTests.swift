import XCTest

final class RHVoiceSilenceAnalyzerTests: XCTestCase {
    func testMeasuresLeadingAndTrailingSilence() {
        let samples: [Float] = [0, 0.0005, 0.2, -0.3, 0.0004, 0]
        let silence = RHVoiceSilenceAnalyzer.measure(samples: samples, sampleRate: 1_000)

        XCTAssertEqual(silence.leadingSamples, 2)
        XCTAssertEqual(silence.trailingSamples, 2)
        XCTAssertEqual(silence.leadingSilenceMs, 2)
        XCTAssertEqual(silence.trailingSilenceMs, 2)
    }

    func testTrimsOnlyRequestedSides() {
        let samples: [Float] = [0, 0, 0.2, 0.3, 0, 0]

        XCTAssertEqual(
            RHVoiceSilenceAnalyzer.trimMidSentenceSilence(
                samples: samples,
                sampleRate: 1_000,
                trimLeading: true,
                trimTrailing: false
            ),
            [0.2, 0.3, 0, 0]
        )
        XCTAssertEqual(
            RHVoiceSilenceAnalyzer.trimMidSentenceSilence(
                samples: samples,
                sampleRate: 1_000,
                trimLeading: false,
                trimTrailing: true
            ),
            [0, 0, 0.2, 0.3]
        )
    }

    func testTrimIsLimitedTo250MillisecondsPerSide() {
        let samples = Array(repeating: Float(0), count: 300) + [0.4] + Array(repeating: Float(0), count: 300)
        let trimmed = RHVoiceSilenceAnalyzer.trimMidSentenceSilence(
            samples: samples,
            sampleRate: 1_000,
            trimLeading: true,
            trimTrailing: true
        )

        XCTAssertEqual(trimmed.count, 101)
        XCTAssertEqual(trimmed.first, 0)
        XCTAssertEqual(trimmed[50], 0.4)
        XCTAssertEqual(trimmed.last, 0)
    }
}
