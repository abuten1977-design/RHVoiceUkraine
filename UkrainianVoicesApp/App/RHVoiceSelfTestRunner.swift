import Foundation
import RHVoiceKit

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
