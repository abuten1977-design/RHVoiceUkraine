import AVFoundation
import AVFAudio
import CoreAudio
import CoreMedia
import Foundation
import RHVoiceBridge
import os.log

private let paramLog = OSLog(subsystem: "com.rhvoice.UkrainianVoices", category: "params")

private func rhLog(_ msg: String) {
    msg.withCString { RHVoiceDebugLogString($0) }
}

@available(iOS 16.0, macOS 13.0, *)
@objc(UkrainianSpeechSynthesizer)
public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!

    // eSpeak-style: flat array + offset + semaphore
    private var output: [Float] = []
    private var outputOffset: Int = 0
    private var outputMutex = DispatchSemaphore(value: 1)
    private var isSynthesizing = false

    private static let staticVoices: [AVSpeechSynthesisProviderVoice] = [
        AVSpeechSynthesisProviderVoice(name: "Anatol", identifier: "com.rhvoice.UkrainianVoices.anatol",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
        AVSpeechSynthesisProviderVoice(name: "Natalia", identifier: "com.rhvoice.UkrainianVoices.natalia",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
        AVSpeechSynthesisProviderVoice(name: "Marianna", identifier: "com.rhvoice.UkrainianVoices.marianna",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
        AVSpeechSynthesisProviderVoice(name: "Volodymyr", identifier: "com.rhvoice.UkrainianVoices.volodymyr",
            primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
    ]

    @objc
    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        let basicDescription = AudioStreamBasicDescription(
            mSampleRate: 24000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let format = AVAudioFormat(cmAudioFormatDescription: try CMAudioFormatDescription(audioStreamBasicDescription: basicDescription))
        self.outputBus = try AUAudioUnitBus(format: format)

        try super.init(componentDescription: componentDescription, options: options)

        self._outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        _ = self.rhvoiceEngine
    }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { Self.staticVoices }
        set { }
    }

    // MARK: - Render (exactly like eSpeak)

    private func performRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
        renderEvents: UnsafePointer<AURenderEvent>?,
        renderPull: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        let unsafeBuffer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        let frames = unsafeBuffer[0].mData!.assumingMemoryBound(to: Float.self)
        frames.assign(repeating: 0, count: Int(frameCount))

        self.outputMutex.wait()
        
        let available = self.output.count - self.outputOffset
        
        if available <= 0 {
            let stillSynthesizing = self.isSynthesizing
            self.outputMutex.signal()
            
            outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(Int(frameCount) * MemoryLayout<Float>.size)
            
            if stillSynthesizing {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }

        let count = min(available, Int(frameCount))
        self.output.withUnsafeBufferPointer { ptr in
            frames.assign(from: ptr.baseAddress!.advanced(by: self.outputOffset), count: count)
        }
        outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(count * MemoryLayout<Float>.size)

        self.outputOffset += count
        
        let done = (self.outputOffset >= self.output.count) && !self.isSynthesizing
        
        if done {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            self.output.removeAll()
            self.outputOffset = 0
        } else {
            actionFlags.pointee = .offlineUnitRenderAction_Render
        }
        self.outputMutex.signal()

        return noErr
    }

    public override var internalRenderBlock: AUInternalRenderBlock { self.performRender }

    // MARK: - Synthesize (exactly like eSpeak: sync, then store under mutex)

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let text = speechRequest.ssmlRepresentation
        let voiceId = speechRequest.voice.identifier

        rhLog("synth request: voice=\(voiceId) text=\(text.count) chars")

        // Resolve voice profile name
        let profileName: String
        if let descriptor = RHVoiceSharedSettings.voiceCatalog.first(where: { $0.identifier == voiceId }) {
            profileName = descriptor.profileName
        } else {
            profileName = RHVoiceSharedSettings.voiceCatalog.first!.profileName
        }

        // Extract rate/volume from SSML
        let ssmlRatePercent = Self.extractSSMLRatePercent(from: text)
        let ssmlVolume = Self.extractSSMLVolume(from: text)

        // Read user settings from App Group
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
        let voiceSettings = snapshot.effectiveSettings(for: voiceId)

        // VoiceOver rotor owns speed. The legacy app accelerator is pinned off.
        let mappedRate = Self.mapSSMLRatePercentToEngineMultiplier(ssmlRatePercent)
        let accelerator = Self.clampAccelerator(voiceSettings.speedMultiplier)
        let finalRate = mappedRate * accelerator
        let effectiveVolume = ssmlVolume
        let effectivePitch = 1.0
        let sentencePauseMs = Int(Self.clampSentencePause(voiceSettings.sentencePause).rounded())
        let wordGapMs = Int(Self.clampWordGap(voiceSettings.wordGap).rounded())
        let normalizedText = Self.normalizeApostrophesInTextSegments(text)
        let synthesisText = Self.applyTextBreaks(to: normalizedText, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)

        rhLog("synth: voice=\(profileName) ssmlRate=\(String(format: "%.1f", ssmlRatePercent))% mapped=\(String(format: "%.2f", mappedRate)) accel=\(String(format: "%.2f", accelerator)) final=\(String(format: "%.2f", finalRate)) vol=\(String(format: "%.2f", effectiveVolume)) pitch=\(String(format: "%.2f", effectivePitch)) pauseMs=\(sentencePauseMs) wordGapMs=\(wordGapMs)")
        os_log(.info, log: paramLog, "PARAMS ssmlRatePct=%{public}.1f mappedRate=%{public}.2f accelerator=%{public}.2f finalRate=%{public}.2f vol=%{public}.2f pitch=%{public}.2f pauseMs=%{public}d useCustom=%{public}d wordGapMs=%{public}d", ssmlRatePercent, mappedRate, accelerator, finalRate, effectiveVolume, effectivePitch, sentencePauseMs, (accelerator != 1.0 || wordGapMs > 0 || sentencePauseMs > 0) ? 1 : 0, wordGapMs)

        self.outputMutex.wait()
        self.isSynthesizing = true
        self.output.removeAll()
        self.outputOffset = 0
        self.outputMutex.signal()

        // Synchronous synthesis — blocks until complete
        var pcmBuffer = rhvoiceEngine.synthesize(
            synthesisText,
            voice: profileName,
            rate: finalRate,
            volume: effectiveVolume,
            pitch: effectivePitch
        )
        
        // Fallback: if SSML synthesis failed, try plain text without tags
        if pcmBuffer == nil && synthesisText.contains("<") {
            let plainText = stripSSML(synthesisText)
            rhLog("synth: SSML failed, trying fallback: \(plainText.prefix(50))...")
            pcmBuffer = rhvoiceEngine.synthesize(
                plainText,
                voice: profileName,
                rate: finalRate,
                volume: effectiveVolume,
                pitch: effectivePitch
            )
        }

        self.outputMutex.wait()
        defer {
            self.isSynthesizing = false
            self.outputMutex.signal()
        }

        guard let buffer = pcmBuffer, let floatData = buffer.floatChannelData?[0] else {
            rhLog("synth FAILED")
            return
        }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: floatData, count: frameCount))

        rhLog("synth output: \(samples.count) samples")

        self.output = samples
        self.outputOffset = 0
    }

    private func stripSSML(_ ssml: String) -> String {
        return ssml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    // MARK: - Cancel (exactly like eSpeak)

    public override func cancelSpeechRequest() {
        self.outputMutex.wait()
        self.isSynthesizing = false
        self.output.removeAll()
        self.outputOffset = 0
        rhLog("cancel")
        self.outputMutex.signal()
    }

    // MARK: - Message Channel

    public override func messageChannel(for channelName: String) -> AUMessageChannel {
        final class MC: AUMessageChannel {
            var callHostBlock: CallHostBlock? { get { nil } set {} }
            func callAudioUnit(_ message: [AnyHashable : Any]) -> [AnyHashable : Any] {
                if message["initHost"] as? Bool == true {
                    return [
                        "voiceIds": UkrainianSpeechSynthesizer.staticVoices.map(\.identifier),
                        "voiceNames": UkrainianSpeechSynthesizer.staticVoices.map(\.name),
                        "primaryLanguages": UkrainianSpeechSynthesizer.staticVoices.map { $0.primaryLanguages.first ?? "uk-UA" }
                    ]
                }
                return [:]
            }
        }
        return MC()
    }

    // MARK: - SSML parsing

    private static func extractSSMLRatePercent(from ssml: String) -> Double {
        guard let match = try? NSRegularExpression(pattern: #"rate="([0-9]+(?:\.[0-9]+)?)%""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let pct = Double(ssml[range]) else { return 100.0 }
        return max(0.0, pct)
    }

    private static func mapSSMLRatePercentToEngineMultiplier(_ percent: Double) -> Double {
        let normalizedPercent = max(0.0, percent)
#if os(macOS)
        if normalizedPercent <= 100.0 {
            return pow(4.0, (normalizedPercent - 50.0) / 50.0)
        }
        let progress = min((normalizedPercent - 100.0) / 324.0, 1.0)
        return 4.0 * pow(1.125, progress)
#else
        let proportionalRate = normalizedPercent / 100.0
        return min(max(proportionalRate, 0.5), 2.0)
#endif
    }

    private static func clampAccelerator(_ value: Double) -> Double {
        1.0
    }

    private static func clampSentencePause(_ value: Double) -> Double {
        min(max(value, 0.0), 2_000.0)
    }

    private static func clampWordGap(_ value: Double) -> Double {
        min(max(value, 0.0), 300.0)
    }

    private static func normalizeApostrophesInTextSegments(_ ssml: String) -> String {
        var output = ""
        var textSegment = ""
        var tagSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tagSegment.append(character)
                if character == ">" {
                    output += normalizeApostrophes(textSegment)
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
            output += normalizeApostrophes(textSegment) + tagSegment
        } else {
            output += normalizeApostrophes(textSegment)
        }
        return output
    }

    private static func normalizeApostrophes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    private static func applyTextBreaks(to ssml: String, sentencePauseMs: Int, wordGapMs: Int) -> String {
        guard sentencePauseMs > 0 || wordGapMs > 0 else { return ssml }

        var output = ""
        var textSegment = ""
        var tagSegment = ""
        var insideTag = false

        for character in ssml {
            if insideTag {
                tagSegment.append(character)
                if character == ">" {
                    output += transformTextSegment(textSegment, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)
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
            output += textSegment + tagSegment
        } else {
            output += transformTextSegment(textSegment, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)
        }

        if output.range(of: #"<\s*speak\b"#, options: .regularExpression) != nil {
            return output
        }
        return "<speak>\(output)</speak>"
    }

    private static func transformTextSegment(_ text: String, sentencePauseMs: Int, wordGapMs: Int) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        var output = ""
        for index in characters.indices {
            let character = characters[index]
            output.append(character)

            if sentencePauseMs > 0 && isSentencePunctuation(character) && !isDecimalSeparator(characters, at: index) {
                output += "<break time='\(sentencePauseMs)ms'/>"
            }

            if wordGapMs > 0 && isWordCharacter(character) {
                let nextIndex = index + 1
                if nextIndex < characters.count, isWhitespace(characters[nextIndex]), nextWordStarts(afterWhitespaceFrom: nextIndex, in: characters) {
                    output += "<break time='\(wordGapMs)ms'/>"
                }
            }
        }
        return output
    }

    private static func nextWordStarts(afterWhitespaceFrom index: Int, in characters: [Character]) -> Bool {
        var cursor = index
        while cursor < characters.count, isWhitespace(characters[cursor]) {
            cursor += 1
        }
        return cursor < characters.count && isWordCharacter(characters[cursor])
    }

    private static func isSentencePunctuation(_ character: Character) -> Bool {
        character == "." || character == "," || character == "!" || character == "?"
    }

    private static func isDecimalSeparator(_ characters: [Character], at index: Int) -> Bool {
        guard characters[index] == "." || characters[index] == "," else { return false }
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        return previous?.isNumber == true && next?.isNumber == true
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    private static func extractSSMLVolume(from ssml: String) -> Double {
        guard let match = try? NSRegularExpression(pattern: #"volume="([+-]?[0-9]+(?:\.[0-9]+)?)dB""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let db = Double(ssml[range]) else { return 1.0 }
        return max(0.1, min(2.0, pow(10.0, db / 20.0)))
    }
}
