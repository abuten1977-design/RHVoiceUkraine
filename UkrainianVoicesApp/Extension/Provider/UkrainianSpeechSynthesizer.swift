import AVFoundation
import AVFAudio
import CoreAudio
import CoreMedia
import Foundation
import RHVoiceBridge

private func rhLog(_ msg: String) {
    msg.withCString { RHVoiceDebugLogString($0) }
}

private enum RHVoiceParam: AUParameterAddress {
    case speedMultiplier = 1
    case volume = 2
    case pitch = 3
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

    // AUParameters (like eSpeak) — no App Group needed
    private var paramSpeedMultiplier: AUParameter!
    private var paramVolume: AUParameter!
    private var paramPitch: AUParameter!

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

        // Setup AUParameters (like eSpeak)
        paramSpeedMultiplier = AUParameterTree.createParameter(
            withIdentifier: "speedMultiplier", name: "Speed Multiplier",
            address: RHVoiceParam.speedMultiplier.rawValue,
            min: 0.5, max: 3.0, unit: .generic, unitName: nil,
            valueStrings: nil, dependentParameters: nil)
        paramSpeedMultiplier.value = 1.0

        paramVolume = AUParameterTree.createParameter(
            withIdentifier: "volume", name: "Volume",
            address: RHVoiceParam.volume.rawValue,
            min: 0.1, max: 2.0, unit: .generic, unitName: nil,
            valueStrings: nil, dependentParameters: nil)
        paramVolume.value = 1.0

        paramPitch = AUParameterTree.createParameter(
            withIdentifier: "pitch", name: "Pitch",
            address: RHVoiceParam.pitch.rawValue,
            min: 0.5, max: 2.0, unit: .generic, unitName: nil,
            valueStrings: nil, dependentParameters: nil)
        paramPitch.value = 1.0

        self.parameterTree = AUParameterTree.createTree(withChildren: [
            paramSpeedMultiplier, paramVolume, paramPitch
        ])

        self.parameterTree?.implementorValueProvider = { [weak self] param in
            guard let self = self else { return 1.0 }
            switch param.address {
            case RHVoiceParam.speedMultiplier.rawValue: return self.paramSpeedMultiplier.value
            case RHVoiceParam.volume.rawValue: return self.paramVolume.value
            case RHVoiceParam.pitch.rawValue: return self.paramPitch.value
            default: return 1.0
            }
        }
        self.parameterTree?.implementorValueObserver = { [weak self] param, value in
            guard let self = self else { return }
            switch param.address {
            case RHVoiceParam.speedMultiplier.rawValue: self.paramSpeedMultiplier.value = value
            case RHVoiceParam.volume.rawValue: self.paramVolume.value = value
            case RHVoiceParam.pitch.rawValue: self.paramPitch.value = value
            default: break
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

    // MARK: - Render (eSpeak-style)

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
            actionFlags.pointee = stillSynthesizing ? .offlineUnitRenderAction_Render : .offlineUnitRenderAction_Complete
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

    // MARK: - Synthesize

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

        // Get parameters from AUParameterTree
        let speedMult = Double(paramSpeedMultiplier.value)
        let userVolume = Double(paramVolume.value)
        let userPitch = Double(paramPitch.value)

        // Extract rate/volume from SSML (VoiceOver sends these)
        let ssmlRate = Self.extractSSMLRate(from: text)
        let ssmlVolume = Self.extractSSMLVolume(from: text)

        // Combine: SSML rate * speedMultiplier, log curve above 2.0
        let mappedRate = ssmlRate <= 2.0 ? ssmlRate : 2.0 + log(ssmlRate / 2.0) * 1.5
        let effectiveRate = mappedRate * speedMult
        let cappedRate = min(effectiveRate, 4.0)
        let effectiveVolume = ssmlVolume * userVolume
        let effectivePitch = userPitch

        rhLog("synth: voice=\(profileName) rate=\(String(format: "%.2f", cappedRate)) vol=\(String(format: "%.2f", effectiveVolume)) pitch=\(String(format: "%.2f", effectivePitch))")

        self.outputMutex.wait()
        self.isSynthesizing = true
        self.output.removeAll()
        self.outputOffset = 0
        self.outputMutex.signal()

        // Synchronous synthesis
        guard let pcmBuffer = rhvoiceEngine.synthesize(
            text,
            voice: profileName,
            rate: cappedRate,
            volume: effectiveVolume,
            pitch: effectivePitch
        ), let floatData = pcmBuffer.floatChannelData?[0] else {
            rhLog("synth FAILED")
            self.outputMutex.wait()
            self.isSynthesizing = false
            self.outputMutex.signal()
            return
        }

        let frameCount = Int(pcmBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: floatData, count: frameCount))
        rhLog("synth output: \(samples.count) samples")

        self.outputMutex.wait()
        self.output = samples
        self.outputOffset = 0
        self.isSynthesizing = false
        self.outputMutex.signal()
    }

    // MARK: - Cancel

    public override func cancelSpeechRequest() {
        rhLog("cancel")
        rhvoiceEngine.cancel()
        self.outputMutex.wait()
        self.isSynthesizing = false
        self.output.removeAll()
        self.outputOffset = 0
        self.outputMutex.signal()
    }

    // MARK: - Message Channel

    public override func messageChannel(for channelName: String) -> AUMessageChannel {
        final class MC: AUMessageChannel {
            weak var unit: UkrainianSpeechSynthesizer?
            var callHostBlock: CallHostBlock? { get { nil } set {} }
            func callAudioUnit(_ message: [AnyHashable : Any]) -> [AnyHashable : Any] {
                guard let unit = unit else { return [:] }
                if message["initHost"] as? Bool == true {
                    return [
                        "voiceIds": UkrainianSpeechSynthesizer.staticVoices.map(\.identifier),
                        "voiceNames": UkrainianSpeechSynthesizer.staticVoices.map(\.name),
                        "speedMultiplier": unit.paramSpeedMultiplier.value,
                        "volume": unit.paramVolume.value,
                        "pitch": unit.paramPitch.value
                    ]
                }
                // Allow app to set parameters via message channel
                if let speed = message["speedMultiplier"] as? Float {
                    unit.paramSpeedMultiplier.value = speed
                }
                if let vol = message["volume"] as? Float {
                    unit.paramVolume.value = vol
                }
                if let pitch = message["pitch"] as? Float {
                    unit.paramPitch.value = pitch
                }
                return ["ok": true]
            }
        }
        let mc = MC()
        mc.unit = self
        return mc
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
