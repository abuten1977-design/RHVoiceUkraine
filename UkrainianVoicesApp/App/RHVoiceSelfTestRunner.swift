import Foundation
import AVFoundation
#if os(iOS)
import RHVoiceBridge
#else
import RHVoiceKit
#endif

@MainActor
enum RHVoiceSelfTestRunner {
    static func runAndExit() async {
        let logPath = "/tmp/rhvoice_selftest.log"
        var lines: [String] = []
        lines.append("RHVoice self-test started: \(Date())")
        fputs("RHVoice self-test started\n", stderr)

        // Give SwiftUI a moment to finish launching its runtime.
        try? await Task.sleep(nanoseconds: 200_000_000)

        let engine = RHVoiceEngine()
        let voices: [(name: String, sample: String)] = [
            ("Anatol", "Привіт! Це тест голосу Анатол."),
            ("Marianna", "Привіт! Це тест голосу Маріанна."),
            ("Natalia", "Привіт! Це тест голосу Наталія."),
            ("Volodymyr", "Привіт! Це тест голосу Володимир.")
        ]
        let clipDirectory = ProcessInfo.processInfo.environment["RHVOICE_SELFTEST_CLIP_DIR"]

        for v in voices {
            let start = Date()
            let startLine = "START voice=\(v.name) at=\(start)"
            lines.append(startLine)
            fputs("\(startLine)\n", stderr)
            let buffer = engine.synthesize(v.sample, voice: v.name, rate: 0.5, volume: 1.0, pitch: 1.0)
            if let buffer {
                let okLine = "OK voice=\(v.name) frames=\(buffer.frameLength) sampleRate=\(Int(buffer.format.sampleRate)) duration=\(Date().timeIntervalSince(start))"
                lines.append(okLine)
                fputs("\(okLine)\n", stderr)
            } else {
                let failLine = "FAIL voice=\(v.name) buffer=nil duration=\(Date().timeIntervalSince(start))"
                lines.append(failLine)
                fputs("\(failLine)\n", stderr)
            }
        }

        if let clipDirectory, !clipDirectory.isEmpty {
            let proofPhrase = "Це тестова фраза для перевірки швидкості мовлення."
            let proofSSML = "<speak>\(proofPhrase)</speak>"
            let proofRates: [(percent: Int, multiplier: Double)] = [
                (50, 0.5),
                (100, 1.0),
                (150, 1.5),
                (200, 2.0),
                (300, 3.0)
            ]
            let clipURL = URL(fileURLWithPath: clipDirectory, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: clipURL, withIntermediateDirectories: true)
                if let buffer = engine.synthesize(proofSSML, voice: "Anatol", rate: 1.0, volume: 1.0, pitch: 1.0),
                   buffer.frameLength > 0 {
                    let outputURL = clipURL.appendingPathComponent("anatol-default.wav")
                    let file = try AVAudioFile(forWriting: outputURL, settings: buffer.format.settings)
                    try file.write(from: buffer)
                    let line = String(format: "CLIP OK default path=%@ frames=%u duration=%.3f",
                                      outputURL.path,
                                      buffer.frameLength,
                                      Double(buffer.frameLength) / buffer.format.sampleRate)
                    lines.append(line)
                    fputs("\(line)\n", stderr)
                } else {
                    let failLine = "CLIP FAIL default buffer=nil"
                    lines.append(failLine)
                    fputs("\(failLine)\n", stderr)
                }

                for point in proofRates {
                    let fileName = "anatol-rate-\(point.percent)p.wav"
                    let outputURL = clipURL.appendingPathComponent(fileName)
                    let buffer = engine.synthesize(proofSSML, voice: "Anatol", rate: point.multiplier, volume: 1.0, pitch: 1.0)
                    guard let buffer, let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
                        let failLine = "CLIP FAIL percent=\(point.percent) rate=\(point.multiplier) buffer=nil"
                        lines.append(failLine)
                        fputs("\(failLine)\n", stderr)
                        continue
                    }

                    let frameCount = Int(buffer.frameLength)
                    let samples = UnsafeBufferPointer(start: channel, count: frameCount)
                    var peak: Float = 0
                    var sumSquares: Double = 0
                    var finite = true
                    for sample in samples {
                        finite = finite && sample.isFinite
                        peak = max(peak, abs(sample))
                        sumSquares += Double(sample * sample)
                    }
                    let rms = sqrt(sumSquares / Double(max(frameCount, 1)))
                    let clipped = peak >= 0.999
                    let silent = rms < 0.0001

                    let file = try AVAudioFile(forWriting: outputURL, settings: buffer.format.settings)
                    try file.write(from: buffer)

                    let ok = finite && !silent && !clipped
                    let line = String(format: "CLIP %@ percent=%d rate=%.1f path=%@ frames=%u peak=%.4f rms=%.6f duration=%.3f",
                                      ok ? "OK" : "FAIL",
                                      point.percent,
                                      point.multiplier,
                                      outputURL.path,
                                      buffer.frameLength,
                                      peak,
                                      rms,
                                      Double(buffer.frameLength) / buffer.format.sampleRate)
                    lines.append(line)
                    fputs("\(line)\n", stderr)
                }
            } catch {
                let failLine = "CLIP FAIL error=\(error)"
                lines.append(failLine)
                fputs("\(failLine)\n", stderr)
            }
        }

        let out = lines.joined(separator: "\n") + "\n"
        do {
            try out.write(toFile: logPath, atomically: true, encoding: .utf8)
        } catch {
            // Best-effort fallback: print to stderr so SSH can capture it.
            fputs("Failed to write \(logPath): \(error)\n", stderr)
            fputs(out, stderr)
        }

        exit(0)
    }
}
