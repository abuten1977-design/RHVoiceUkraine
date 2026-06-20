#if DEBUG
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
        if ProcessInfo.processInfo.environment["RHVOICE_DEBUG_LOG_PROOF"] == "1" {
            runDebugLogProof(lines: &lines)
            writeLogAndExit(lines: lines, logPath: logPath)
        }
        if ProcessInfo.processInfo.environment["RHVOICE_LATENCY_DIAG"] == "1" {
            runLatencyDiagnostics(engine: engine, lines: &lines)
            writeLogAndExit(lines: lines, logPath: logPath)
        }
        if ProcessInfo.processInfo.environment["RHVOICE_TASK057_BASELINE"] == "1" {
            runTask057Baseline(engine: engine, lines: &lines)
            writeLogAndExit(lines: lines, logPath: logPath)
        }
        if ProcessInfo.processInfo.environment["RHVOICE_TASK059_SPLITTER_PROOF"] == "1" {
            runTask059SplitterProof(lines: &lines)
            writeLogAndExit(lines: lines, logPath: logPath)
        }
        if ProcessInfo.processInfo.environment["RHVOICE_SUBSENTENCE_PROOF"] == "1" {
            runSubSentenceProof(engine: engine, lines: &lines)
            writeLogAndExit(lines: lines, logPath: logPath)
        }

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

        writeLogAndExit(lines: lines, logPath: logPath)
    }

    private static func runDebugLogProof(lines: inout [String]) {
        guard let logURL = DebugLogShareHelper.logURL else {
            let line = "DEBUG_LOG_PROOF FAIL appGroupURL=nil"
            lines.append(line)
            fputs("\(line)\n", stderr)
            return
        }

        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "TASK049_BEFORE_CLEAR\n".write(to: logURL, atomically: true, encoding: .utf8)
        let beforeSize = DebugLogShareHelper.logSize()

        DebugLogShareHelper.clearLog()
        let afterClearSize = DebugLogShareHelper.logSize()

        "LATENCY_DIAG TASK049 NSLog fallback proof".withCString { RHVoiceDebugLogString($0) }
        Thread.sleep(forTimeInterval: 0.2)
        let afterLatencyWriteSize = DebugLogShareHelper.logSize()

        let result = (beforeSize > 0 && afterClearSize == 0 && afterLatencyWriteSize > 0) ? "OK" : "FAIL"
        let line = "DEBUG_LOG_PROOF \(result) path=\(logURL.path) beforeSize=\(beforeSize) afterClearSize=\(afterClearSize) afterLatencyWriteSize=\(afterLatencyWriteSize)"
        lines.append(line)
        fputs("\(line)\n", stderr)
    }

    private static func runLatencyDiagnostics(engine: RHVoiceEngine, lines: inout [String]) {
        let cases: [(label: String, text: String)] = [
            ("len10", "Це тестове"),
            ("len40", "Це короткий український текст без меж"),
            ("len80", "Це український текст середньої довжини без крапок і знаків оклику для перевірки"),
            ("len150", "Це довгий український фрагмент без крапок і знаків оклику який має показати чи час синтезу першого фрагмента росте разом із кількістю символів"),
            ("len300", "Це дуже довгий український фрагмент без крапок і знаків оклику який імітує одне велике повідомлення у месенджері з кількома комами, кількома уточненнями, додатковими словами і довгими описами, щоб перевірити чи RHVoice створює велику початкову затримку перед тим як віддати перший аудіобуфер користувачеві VoiceOver")
        ]

        for testCase in cases {
            for iteration in 1...3 {
                let ssml = "<speak>\(testCase.text)</speak>"
                let start = Date()
                let buffer = engine.synthesize(ssml, voice: "Anatol", rate: 1.0, volume: 1.0, pitch: 1.0)
                let synthMs = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
                if let buffer, buffer.frameLength > 0 {
                    let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                    let line = String(format: "LATENCY_DIAG_PHASE_A label=%@ iteration=%d textChars=%d firstFragmentSynthMs=%d totalSynthMs=%d frames=%u audioDuration=%.3f",
                                      testCase.label,
                                      iteration,
                                      testCase.text.count,
                                      synthMs,
                                      synthMs,
                                      buffer.frameLength,
                                      duration)
                    lines.append(line)
                    fputs("\(line)\n", stderr)
                } else {
                    let line = "LATENCY_DIAG_PHASE_A_FAIL label=\(testCase.label) iteration=\(iteration) textChars=\(testCase.text.count) buffer=nil"
                    lines.append(line)
                    fputs("\(line)\n", stderr)
                }
            }
        }
    }

    private static func runTask057Baseline(engine: RHVoiceEngine, lines: inout [String]) {
        let cases: [(label: String, text: String)] = [
            ("short-15", "Доброго дня всім!"),
            ("medium-100", "Доброго дня. Я працюю у Києві. Маю новини: завтра, п'ятого травня, відбудеться зустріч о тринадцятій годині."),
            ("long-300", "Незрячий користувач отримує доступ до тексту через системний синтез мовлення VoiceOver. Якість голосу впливає на швидкість читання, рівень втоми і взагалі на бажання користуватись пристроєм. Чотири українські голоси RHVoice — Anatol, Marianna, Natalia і Volodymyr — створені, щоб дати україномовним альтернативу штатній Лесі."),
            ("cold-start", "Доброго дня всім!")
        ]

        for testCase in cases {
            if testCase.label == "cold-start" {
                let line = "TASK057_BASELINE cold-start-marker idleSeconds=external"
                lines.append(line)
                fputs("\(line)\n", stderr)
            }

            for iteration in 1...3 {
                let ssml = "<speak>\(testCase.text)</speak>"
                let fragments = RHVoicePipelineSplitter.sentencePipelineFragments(from: ssml)
                let start = Date()
                let buffer = engine.synthesize(ssml, voice: "Anatol", rate: 1.0, volume: 1.0, pitch: 1.0)
                let synthMs = Int((Date().timeIntervalSince(start) * 1000.0).rounded())

                if let buffer, buffer.frameLength > 0 {
                    let firstFragmentChars = fragments.first.map(RHVoicePipelineSplitter.textCharacterCount) ?? testCase.text.count
                    let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                    let line = String(format: "TASK057_BASELINE label=%@ iteration=%d textChars=%d fragments=%d firstFragmentChars=%d firstFragmentSynthMs=%d totalSynthMs=%d frames=%u audioDuration=%.3f",
                                      testCase.label,
                                      iteration,
                                      testCase.text.count,
                                      fragments.count,
                                      firstFragmentChars,
                                      synthMs,
                                      synthMs,
                                      buffer.frameLength,
                                      duration)
                    lines.append(line)
                    fputs("\(line)\n", stderr)
                } else {
                    let line = "TASK057_BASELINE_FAIL label=\(testCase.label) iteration=\(iteration) textChars=\(testCase.text.count) buffer=nil"
                    lines.append(line)
                    fputs("\(line)\n", stderr)
                }
            }
        }
    }

    private static func runTask059SplitterProof(lines: inout [String]) {
        let cases: [(label: String, text: String, maxFirstIfPossible: Int)] = [
            ("short_unchanged", "Доброго дня всім!", 30),
            ("medium_sentence", "Доброго дня. Я працюю у Києві. Маю новини: завтра, п'ятого травня, відбудеться зустріч.", 30),
            ("long_no_comma", "Незрячий користувач отримує доступ до тексту через системний синтез мовлення VoiceOver.", 30),
            ("long_comma", "Це довге повідомлення для перевірки швидкого старту, воно містить кілька частин і природні паузи.", 30),
            ("long_dash", "Це довге повідомлення для перевірки швидкого старту — і ще один довгий опис для синтезатора.", 30),
            ("long_parenthesis", "Перше довге повідомлення (з коротким уточненням) має починатися без великої тиші перед першим словом.", 30),
            ("abbrev", "США і НАТО обговорюють нові рішення для України на наступному тижні.", 30),
            ("quoted", "«Українські голоси» мають швидко починати довге повідомлення без відчутної паузи.", 30),
            ("numbers", "Сьогодні о тринадцятій годині двадцять п'ять хвилин відбудеться коротка зустріч.", 30),
            ("unbreakable", "Наддовгесловобезпробілівякенеможнарозрізатибезпсуваннявимови", 80)
        ]

        for testCase in cases {
            let ssml = "<speak>\(testCase.text)</speak>"
            let fragments = RHVoicePipelineSplitter.pipelineFragments(from: ssml)
            let firstChars = fragments.first.map { RHVoicePipelineSplitter.textCharacterCount(in: $0.ssml) } ?? 0
            let ok = firstChars <= testCase.maxFirstIfPossible
            let line = String(format: "TASK059_SPLITTER_PROOF %@ label=%@ textChars=%d fragments=%d firstFragmentChars=%d",
                              ok ? "OK" : "FAIL",
                              testCase.label,
                              testCase.text.count,
                              fragments.count,
                              firstChars)
            lines.append(line)
            fputs("\(line)\n", stderr)
        }
    }

    private static func runSubSentenceProof(engine: RHVoiceEngine, lines: inout [String]) {
        let cases: [(label: String, text: String)] = [
            ("short", "Це коротка фраза."),
            ("long_single", "Це довге повідомлення для перевірки швидкого старту, воно містить кілька частин, додаткові уточнення, природні паузи через кому, важливий фрагмент після тире — і ще один довгий опис, щоб синтезатор не чекав завершення всього речення перед першим аудіо"),
            ("multi", "Перше довге речення має кілька частин, уточнення через кому, і довший опис для перевірки старту. Друге речення теж містить багато слів, додаткові фрагменти, і природну структуру без нових штучних пауз. Третє речення завершує перевірку, має тире — і достатню довжину для поділу.")
        ]
        let clipDirectory = ProcessInfo.processInfo.environment["RHVOICE_SELFTEST_CLIP_DIR"]
        let clipURL = clipDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let clipURL {
            try? FileManager.default.createDirectory(at: clipURL, withIntermediateDirectories: true)
        }

        for testCase in cases {
            let ssml = "<speak>\(testCase.text)</speak>"
            let fragments = RHVoicePipelineSplitter.pipelineFragments(from: ssml)
            var totalSynthMs = 0
            var firstFragmentSynthMs = 0
            var totalFrames = 0
            var outputSamples: [Float] = []
            var outputFormat: AVAudioFormat?
            var failed = false

            for (index, pipelineFragment) in fragments.enumerated() {
                let fragment = pipelineFragment.ssml
                let start = Date()
                guard let buffer = engine.synthesize(fragment, voice: "Anatol", rate: 1.0, volume: 1.0, pitch: 1.0),
                      let channel = buffer.floatChannelData?[0],
                      buffer.frameLength > 0 else {
                    failed = true
                    break
                }

                let synthMs = Int((Date().timeIntervalSince(start) * 1000.0).rounded())
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                let silence = RHVoiceSilenceAnalyzer.measure(samples: samples, sampleRate: buffer.format.sampleRate)
                let trimLeading = pipelineFragment.continuesSentence
                let trimTrailing = index + 1 < fragments.count && fragments[index + 1].continuesSentence
                let trimmedSamples = RHVoiceSilenceAnalyzer.trimMidSentenceSilence(
                    samples: samples,
                    sampleRate: buffer.format.sampleRate,
                    trimLeading: trimLeading,
                    trimTrailing: trimTrailing
                )
                let fragmentLine = String(format: "TASK081_SILENCE label=%@ fragment=%d chars=%d leadingSilenceMs=%d trailingSilenceMs=%d trimLeading=%d trimTrailing=%d synthMs=%d frames=%u trimmedFrames=%d",
                                          testCase.label,
                                          index + 1,
                                          RHVoicePipelineSplitter.textCharacterCount(in: fragment),
                                          silence.leadingSilenceMs,
                                          silence.trailingSilenceMs,
                                          trimLeading ? 1 : 0,
                                          trimTrailing ? 1 : 0,
                                          synthMs,
                                          buffer.frameLength,
                                          trimmedSamples.count)
                lines.append(fragmentLine)
                fputs("\(fragmentLine)\n", stderr)
                if index == 0 {
                    firstFragmentSynthMs = synthMs
                }
                totalSynthMs += synthMs
                totalFrames += Int(buffer.frameLength)
                outputFormat = outputFormat ?? buffer.format
                outputSamples.append(contentsOf: trimmedSamples)
            }

            var clipPath = ""
            if !failed,
               let clipURL,
               let format = outputFormat,
               let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(outputSamples.count)) {
                combined.frameLength = AVAudioFrameCount(outputSamples.count)
                if let channel = combined.floatChannelData?[0] {
                    for (index, sample) in outputSamples.enumerated() {
                        channel[index] = sample
                    }
                }
                let outputURL = clipURL.appendingPathComponent("task048-\(testCase.label).wav")
                do {
                    let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                    try file.write(from: combined)
                    clipPath = outputURL.path
                } catch {
                    failed = true
                }
            }

            let firstFragmentChars = fragments.first.map { RHVoicePipelineSplitter.textCharacterCount(in: $0.ssml) } ?? 0
            let line = String(format: "TASK048_PROOF %@ label=%@ textChars=%d fragments=%d firstFragmentChars=%d firstFragmentSynthMs=%d totalSynthMs=%d frames=%d clip=%@",
                              failed ? "FAIL" : "OK",
                              testCase.label,
                              testCase.text.count,
                              fragments.count,
                              firstFragmentChars,
                              firstFragmentSynthMs,
                              totalSynthMs,
                              totalFrames,
                              clipPath)
            lines.append(line)
            fputs("\(line)\n", stderr)
        }
    }

    private static func writeLogAndExit(lines: [String], logPath: String) -> Never {
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
#endif
