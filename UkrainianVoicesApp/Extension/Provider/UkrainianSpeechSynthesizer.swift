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

        // Combine VoiceOver SSML with the app-only accelerator.
        let mappedRate = Self.mapSSMLRatePercentToEngineMultiplier(ssmlRatePercent)
        let accelerator = Self.clampAccelerator(voiceSettings.speedMultiplier)
        let finalRate = mappedRate * accelerator
        let effectiveVolume = ssmlVolume * voiceSettings.volume
        let effectivePitch = voiceSettings.pitch
        let synthesisText = Self.applySentencePause(to: text, milliseconds: voiceSettings.sentencePause)

        rhLog("synth: voice=\(profileName) ssmlRate=\(String(format: "%.1f", ssmlRatePercent))% mapped=\(String(format: "%.2f", mappedRate)) accel=\(String(format: "%.2f", accelerator)) final=\(String(format: "%.2f", finalRate)) vol=\(String(format: "%.2f", effectiveVolume)) pitch=\(String(format: "%.2f", effectivePitch)) pauseMs=\(Int(Self.clampSentencePause(voiceSettings.sentencePause)))")
        os_log(.info, log: paramLog, "PARAMS ssmlRatePct=%{public}.1f mappedRate=%{public}.2f accelerator=%{public}.2f finalRate=%{public}.2f vol=%{public}.2f pitch=%{public}.2f pauseMs=%{public}d useCustom=%{public}d", ssmlRatePercent, mappedRate, accelerator, finalRate, effectiveVolume, effectivePitch, Int(Self.clampSentencePause(voiceSettings.sentencePause)), accelerator != 1.0 ? 1 : 0)

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
        if percent <= 100.0 {
            return 0.5 + (max(0.0, percent) / 100.0) * 0.5
        }
#if os(macOS)
        let upperVoiceOverPercent = 424.0
        let upperBaseRate = 4.0
        let progress = min(max((percent - 100.0) / (upperVoiceOverPercent - 100.0), 0.0), 1.0)
        return pow(upperBaseRate, progress)
#else
        return pow(2.0, (percent - 100.0) / 100.0)
#endif
    }

    private static func clampAccelerator(_ value: Double) -> Double {
        min(max(value, 1.0), 3.0)
    }

    private static func clampSentencePause(_ value: Double) -> Double {
        min(max(value, 0.0), 2_000.0)
    }

    private static func applySentencePause(to ssml: String, milliseconds: Double) -> String {
        let pauseMs = Int(clampSentencePause(milliseconds).rounded())
        guard pauseMs > 0 else { return ssml }

        let breakTag = "<break time='\(pauseMs)ms'/>"
        let paused = ssml.replacingOccurrences(
            of: #"([.,!?])"#,
            with: "$1\(breakTag)",
            options: .regularExpression
        )

        if paused.range(of: #"<\s*speak\b"#, options: .regularExpression) != nil {
            return paused
        }
        return "<speak>\(paused)</speak>"
    }

    private static func extractSSMLVolume(from ssml: String) -> Double {
        guard let match = try? NSRegularExpression(pattern: #"volume="([+-]?[0-9]+(?:\.[0-9]+)?)dB""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let db = Double(ssml[range]) else { return 1.0 }
        return max(0.1, min(2.0, pow(10.0, db / 20.0)))
    }
}
