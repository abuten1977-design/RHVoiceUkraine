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
        let ssmlRate = Self.extractSSMLRate(from: text)
        let ssmlVolume = Self.extractSSMLVolume(from: text)

        // Read user settings from App Group
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
        let voiceSettings = snapshot.effectiveSettings(for: voiceId)

        // Combine SSML with user settings
        let mappedRate = ssmlRate <= 2.0 ? ssmlRate : 2.0 + log(ssmlRate / 2.0) * 1.5
        let effectiveRate = mappedRate * voiceSettings.speedMultiplier
        let cappedRate = min(effectiveRate, 4.0)
        let effectiveVolume = ssmlVolume * voiceSettings.volume
        let effectivePitch = voiceSettings.pitch

        rhLog("synth: voice=\(profileName) rate=\(String(format: "%.2f", cappedRate)) vol=\(String(format: "%.2f", effectiveVolume)) pitch=\(String(format: "%.2f", effectivePitch))")
        os_log(.info, log: paramLog, "PARAMS rate=%{public}.2f speedMult=%{public}.2f vol=%{public}.2f pitch=%{public}.2f useCustom=%{public}d", cappedRate, voiceSettings.speedMultiplier, effectiveVolume, effectivePitch, voiceSettings.speedMultiplier != 1.0 ? 1 : 0)

        self.outputMutex.wait()
        self.isSynthesizing = true
        self.output.removeAll()
        self.outputOffset = 0
        self.outputMutex.signal()

        // Synchronous synthesis — blocks until complete
        var pcmBuffer = rhvoiceEngine.synthesize(
            text,
            voice: profileName,
            rate: cappedRate,
            volume: effectiveVolume,
            pitch: effectivePitch
        )
        
        // Fallback: if SSML synthesis failed, try plain text without tags
        if pcmBuffer == nil && text.contains("<") {
            let plainText = stripSSML(text)
            rhLog("synth: SSML failed, trying fallback: \(plainText.prefix(50))...")
            pcmBuffer = rhvoiceEngine.synthesize(
                plainText,
                voice: profileName,
                rate: cappedRate,
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

    private static func extractSSMLRate(from ssml: String) -> Double {
        guard let match = try? NSRegularExpression(pattern: #"rate="([0-9]+(?:\.[0-9]+)?)%""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let pct = Double(ssml[range]) else { return 1.0 }
        return max(0.5, pct / 100.0)
    }

    private static func extractSSMLVolume(from ssml: String) -> Double {
        guard let match = try? NSRegularExpression(pattern: #"volume="([+-]?[0-9]+(?:\.[0-9]+)?)dB""#)
            .firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let range = Range(match.range(at: 1), in: ssml),
              let db = Double(ssml[range]) else { return 1.0 }
        return max(0.1, min(2.0, pow(10.0, db / 20.0)))
    }
}
