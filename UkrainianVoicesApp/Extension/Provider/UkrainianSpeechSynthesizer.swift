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

private enum RHVoiceAUParameter: AUParameterAddress {
    case rate, volume, pitch
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
    private var rateValue: AUValue?
    private var volumeValue: AUValue?
    private var pitchValue: AUValue?

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
        self.setupParameterTree()
    }

    private func setupParameterTree() {
        self.parameterTree = .createTree(withChildren: [
            AUParameterTree.createGroup(
                withIdentifier: "rhvoice",
                name: "RHVoice Ukrainian",
                children: [
                    AUParameterTree.createParameter(
                        withIdentifier: "rate",
                        name: "Rate",
                        address: RHVoiceAUParameter.rate.rawValue,
                        min: 0.5,
                        max: 4.5,
                        unit: .rate,
                        unitName: nil,
                        valueStrings: nil,
                        dependentParameters: nil
                    ),
                    AUParameterTree.createParameter(
                        withIdentifier: "volume",
                        name: "Volume",
                        address: RHVoiceAUParameter.volume.rawValue,
                        min: 0.0,
                        max: 1.0,
                        unit: .linearGain,
                        unitName: nil,
                        valueStrings: nil,
                        dependentParameters: nil
                    ),
                    AUParameterTree.createParameter(
                        withIdentifier: "pitch",
                        name: "Pitch",
                        address: RHVoiceAUParameter.pitch.rawValue,
                        min: 0.5,
                        max: 2.0,
                        unit: .customUnit,
                        unitName: "multiplier",
                        valueStrings: nil,
                        dependentParameters: nil
                    ),
                ]
            )
        ])

        self.parameterTree?.implementorValueProvider = { [weak self] parameter in
            guard let self else { return 0 }
            switch parameter.address {
            case RHVoiceAUParameter.rate.rawValue:
                return self.rateValue ?? 1.0
            case RHVoiceAUParameter.volume.rawValue:
                return self.volumeValue ?? 1.0
            case RHVoiceAUParameter.pitch.rawValue:
                return self.pitchValue ?? 1.0
            default:
                return 0
            }
        }

        for parameter in self.parameterTree?.allParameters ?? [] {
            parameter.value = self.parameterTree?.implementorValueProvider(parameter) ?? 0
        }

        self.parameterTree?.implementorValueObserver = { [weak self] parameter, value in
            guard let self else { return }
            switch parameter.address {
            case RHVoiceAUParameter.rate.rawValue:
                self.rateValue = value
            case RHVoiceAUParameter.volume.rawValue:
                self.volumeValue = value
            case RHVoiceAUParameter.pitch.rawValue:
                self.pitchValue = value
            default:
                break
            }
        }
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
        Self.logApostropheEncoding(label: "input-ssml", ssml: text)

        // Resolve voice profile name
        let profileName: String
        if let descriptor = RHVoiceSharedSettings.voiceCatalog.first(where: { $0.identifier == voiceId }) {
            profileName = descriptor.profileName
        } else {
            profileName = RHVoiceSharedSettings.voiceCatalog.first!.profileName
        }

        // Extract rate/volume from SSML
        let ssmlRatePercent = Self.extractSSMLRatePercentIfPresent(from: text)
        let ssmlVolume = Self.extractSSMLVolumeIfPresent(from: text)
        let ssmlPitch = Self.extractSSMLPitch(from: text)
        let ssmlSnippet = String(text.prefix(200))
        rhLog("PITCH_DIAG ssmlSnippet=\(ssmlSnippet)")

        // Read user settings from App Group
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
        let voiceSettings = snapshot.effectiveSettings(for: voiceId)

        let effectiveRatePercent = ssmlRatePercent ?? 100.0
        let mappedRate = ssmlRatePercent.map(Self.mapSSMLRatePercentToEngineMultiplier)
            ?? Double(rateValue ?? 1.0)
        let baselineSpeed = Self.clampSpeedMultiplier(voiceSettings.speedMultiplier)
        let finalRate = Self.clampRate(mappedRate * baselineSpeed)
        let effectiveVolume = ssmlVolume ?? Self.clampVolume(Double(volumeValue ?? 1.0))
        let baselineVolume = Self.clampVolume(voiceSettings.volume)
        let finalVolume = Self.clampVolume(effectiveVolume * baselineVolume)
        let effectivePitch = Self.clampPitch(ssmlPitch ?? voiceSettings.pitch)
        let sentencePauseMs = Int(Self.clampSentencePause(voiceSettings.sentencePause).rounded())
        let wordGapMs = Int(Self.clampWordGap(voiceSettings.wordGap).rounded())
        let normalizedText = Self.normalizeApostrophesInTextSegments(text)
        Self.logApostropheEncoding(label: "after-apostrophe-normalize", ssml: normalizedText)
        let synthesisText = Self.applyTextBreaks(to: normalizedText, sentencePauseMs: sentencePauseMs, wordGapMs: wordGapMs)
        Self.logApostropheEncoding(label: "final-engine-input", ssml: synthesisText)

        rhLog("synth: voice=\(profileName) ssmlRate=\(String(format: "%.1f", effectiveRatePercent))% mapped=\(String(format: "%.2f", mappedRate)) baselineSpeed=\(String(format: "%.2f", baselineSpeed)) final=\(String(format: "%.2f", finalRate)) vol=\(String(format: "%.2f", finalVolume)) baselineVolume=\(String(format: "%.2f", baselineVolume)) pitch=\(String(format: "%.2f", effectivePitch)) pauseMs=\(sentencePauseMs) wordGapMs=\(wordGapMs)")
        os_log(.info, log: paramLog, "PARAMS ssmlRatePct=%{public}.1f mappedRate=%{public}.2f baselineSpeed=%{public}.2f finalRate=%{public}.2f vol=%{public}.2f baselineVolume=%{public}.2f pitch=%{public}.2f pauseMs=%{public}d useCustom=%{public}d wordGapMs=%{public}d", effectiveRatePercent, mappedRate, baselineSpeed, finalRate, finalVolume, baselineVolume, effectivePitch, sentencePauseMs, (rateValue != nil || volumeValue != nil || baselineSpeed != 1.0 || baselineVolume != 1.0 || ssmlPitch != nil || voiceSettings.pitch != 1.0 || wordGapMs > 0 || sentencePauseMs > 0) ? 1 : 0, wordGapMs)

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
            volume: finalVolume,
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
                volume: finalVolume,
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
        extractSSMLRatePercentIfPresent(from: ssml) ?? 100.0
    }

    private static func extractSSMLRatePercentIfPresent(from ssml: String) -> Double? {
        guard let match = try? NSRegularExpression(pattern: #"rate="([0-9]+(?:\.[0-9]+)?)%""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let pct = Double(ssml[range]) else { return nil }
        return max(0.0, pct)
    }

    private static func mapSSMLRatePercentToEngineMultiplier(_ percent: Double) -> Double {
        max(0.1, min(10.0, percent / 100.0))
    }

    private static func clampRate(_ value: Double) -> Double {
        min(max(value, 0.1), 10.0)
    }

    private static func clampSpeedMultiplier(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }

    private static func clampVolume(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private static func clampPitch(_ value: Double) -> Double {
        min(max(value, 0.5), 2.0)
    }

    private static func extractSSMLPitch(from ssml: String) -> Double? {
        guard let match = try? NSRegularExpression(pattern: #"pitch\s*=\s*"([^"]+)""#, options: [.caseInsensitive])
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml) else { return nil }

        let rawPitch = ssml[range].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch rawPitch {
        case "x-low":
            return 0.5
        case "low":
            return 0.75
        case "medium", "default":
            return 1.0
        case "high":
            return 1.25
        case "x-high":
            return 1.5
        default:
            break
        }

        if rawPitch.hasSuffix("%") {
            let numeric = rawPitch.dropLast()
            if let percent = Double(numeric) {
                if numeric.first == "+" || numeric.first == "-" {
                    return 1.0 + (percent / 100.0)
                }
                return percent / 100.0
            }
        }

        if rawPitch.hasSuffix("st"),
           let semitones = Double(rawPitch.dropLast(2)) {
            return pow(2.0, semitones / 12.0)
        }

        if rawPitch.hasSuffix("hz") {
            return nil
        }

        return nil
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
            .replacingOccurrences(of: "&apos;", with: "`")
            .replacingOccurrences(of: "&#39;", with: "`")
            .replacingOccurrences(of: "&#x27;", with: "`")
            .replacingOccurrences(of: "&#X27;", with: "`")
            .replacingOccurrences(of: "\u{0027}", with: "`")
            .replacingOccurrences(of: "\u{2019}", with: "`")
            .replacingOccurrences(of: "\u{02BC}", with: "`")
            .replacingOccurrences(of: "\u{2018}", with: "`")
            .replacingOccurrences(of: "\u{2032}", with: "`")
            .replacingOccurrences(of: "\u{00B4}", with: "`")
            .replacingOccurrences(of: "\u{FF07}", with: "`")
            .replacingOccurrences(of: "\u{0060}", with: "`")
    }

    private static func logApostropheEncoding(label: String, ssml: String) {
        let textSegments = extractTextSegments(from: ssml)
        let matches = textSegments.flatMap { apostropheDiagnostics(in: $0) }

        guard !matches.isEmpty else {
            rhLog("APOSTROPHE_DIAG \(label): no apostrophe-like scalars in text segments")
            return
        }

        for (index, match) in matches.enumerated() {
            rhLog("APOSTROPHE_DIAG \(label)#\(index + 1): \(match)")
        }
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

    private static func apostropheDiagnostics(in text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var results: [String] = []

        for index in scalars.indices where isApostropheLikeScalar(scalars[index]) {
            let wordRange = diagnosticWordRange(around: index, in: scalars)
            let wordScalars = Array(scalars[wordRange])
            let word = String(String.UnicodeScalarView(wordScalars))
            let codepoints = wordScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
            let utf8Bytes = word.utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
            let apostrophe = String(format: "U+%04X", scalars[index].value)
            results.append("apostrophe=\(apostrophe) word=\(word) codepoints=[\(codepoints)] utf8=[\(utf8Bytes)]")
        }

        return results
    }

    private static func isApostropheLikeScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0027, 0x0060, 0x00B4, 0x02BC, 0x055A, 0x2018, 0x2019, 0x2032, 0xA78B, 0xA78C, 0xFF07:
            return true
        default:
            return false
        }
    }

    private static func diagnosticWordRange(around index: Int, in scalars: [UnicodeScalar]) -> Range<Int> {
        var start = index
        var end = index + 1

        while start > scalars.startIndex, isDiagnosticWordScalar(scalars[start - 1]) {
            start -= 1
        }

        while end < scalars.endIndex, isDiagnosticWordScalar(scalars[end]) {
            end += 1
        }

        return start..<end
    }

    private static func isDiagnosticWordScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || isApostropheLikeScalar(scalar)
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
        extractSSMLVolumeIfPresent(from: ssml) ?? 1.0
    }

    private static func extractSSMLVolumeIfPresent(from ssml: String) -> Double? {
        guard let match = try? NSRegularExpression(pattern: #"volume="([+-]?[0-9]+(?:\.[0-9]+)?)dB""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let db = Double(ssml[range]) else { return nil }
        return max(0.1, min(2.0, pow(10.0, db / 20.0)))
    }
}
