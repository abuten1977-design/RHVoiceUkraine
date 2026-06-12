import Foundation

struct RHVoiceSilenceMeasurement {
    let leadingSilenceMs: Int
    let trailingSilenceMs: Int
    let leadingSamples: Int
    let trailingSamples: Int
}

enum RHVoiceSilenceAnalyzer {
    static let silenceThreshold: Float = 0.001
    static let maxTrimMs = 250

    static func measure(samples: [Float], sampleRate: Double) -> RHVoiceSilenceMeasurement {
        guard !samples.isEmpty, sampleRate > 0 else {
            return RHVoiceSilenceMeasurement(leadingSilenceMs: 0, trailingSilenceMs: 0, leadingSamples: 0, trailingSamples: 0)
        }

        let leadingSamples = samples.prefix { abs($0) < silenceThreshold }.count
        let trailingSamples = samples.reversed().prefix { abs($0) < silenceThreshold }.count

        return RHVoiceSilenceMeasurement(
            leadingSilenceMs: samplesToMilliseconds(leadingSamples, sampleRate: sampleRate),
            trailingSilenceMs: samplesToMilliseconds(trailingSamples, sampleRate: sampleRate),
            leadingSamples: leadingSamples,
            trailingSamples: trailingSamples
        )
    }

    static func trimMidSentenceSilence(
        samples: [Float],
        sampleRate: Double,
        trimLeading: Bool,
        trimTrailing: Bool
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0, trimLeading || trimTrailing else {
            return samples
        }

        let silence = measure(samples: samples, sampleRate: sampleRate)
        let maxTrimSamples = Int(((Double(maxTrimMs) / 1000.0) * sampleRate).rounded())
        let leadingTrim = trimLeading ? min(silence.leadingSamples, maxTrimSamples) : 0
        let trailingTrim = trimTrailing ? min(silence.trailingSamples, maxTrimSamples) : 0
        guard leadingTrim + trailingTrim < samples.count else {
            return samples
        }

        return Array(samples[leadingTrim..<(samples.count - trailingTrim)])
    }

    private static func samplesToMilliseconds(_ sampleCount: Int, sampleRate: Double) -> Int {
        Int(((Double(sampleCount) / sampleRate) * 1000.0).rounded())
    }
}
