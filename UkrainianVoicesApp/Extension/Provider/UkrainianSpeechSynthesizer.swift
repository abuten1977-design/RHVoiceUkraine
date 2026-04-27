import AVFoundation
import AVFAudio
import CoreAudio
import CoreMedia
import Foundation
import RHVoiceKit

private enum RHVoiceParameter: AUParameterAddress {
    case rate = 1
    case volume = 2
    case speedMultiplier = 3
    case sentencePause = 4
}

@available(iOS 16.0, macOS 13.0, *)
@objc(UkrainianSpeechSynthesizer)
public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    // Engine is lazy — created only when synthesis is actually requested.
    // This keeps init() lightweight for macOS component discovery (auval).
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus
    private let outputMutex = DispatchSemaphore(value: 1)

    // Static voice list — no dependency on shared settings at init time.
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

    private var outputBussesStorage: AUAudioUnitBusArray!
    private var output: [Float] = []
    private var outputOffset = 0

    private var rateValue: AUValue = 0.5
    private var volumeValue: AUValue = 1.0
    private var speedMultiplierValue: AUValue = 1.0
    private var sentencePauseValue: AUValue = 0.0

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
        let formatDescription = try CMAudioFormatDescription(audioStreamBasicDescription: basicDescription)
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        self.outputBus = try AUAudioUnitBus(format: format)

        try super.init(componentDescription: componentDescription, options: options)

        self.outputBussesStorage = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .output,
            busses: [outputBus]
        )

        // Minimal parameter tree — no groups, just flat parameters
        let rateParam = AUParameterTree.createParameter(
            withIdentifier: "rate", name: "Rate",
            address: RHVoiceParameter.rate.rawValue,
            min: 0.1, max: 2.0, unit: .rate, unitName: nil,
            valueStrings: nil, dependentParameters: nil)
        let volumeParam = AUParameterTree.createParameter(
            withIdentifier: "volume", name: "Volume",
            address: RHVoiceParameter.volume.rawValue,
            min: 0.0, max: 1.0, unit: .linearGain, unitName: nil,
            valueStrings: nil, dependentParameters: nil)

        let tree = AUParameterTree.createTree(withChildren: [rateParam, volumeParam])
        tree.implementorValueProvider = { [weak self] param in
            guard let self else { return 0 }
            return param.address == RHVoiceParameter.rate.rawValue ? self.rateValue : self.volumeValue
        }
        tree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }
            if param.address == RHVoiceParameter.rate.rawValue { self.rateValue = value }
            else if param.address == RHVoiceParameter.volume.rawValue { self.volumeValue = value }
        }
        self.parameterTree = tree
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBussesStorage
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
    }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { Self.staticVoices }
        set { }
    }

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let request = resolvedRequest(for: speechRequest)
        cancelSpeechRequest()

        let audioBuffer = rhvoiceEngine.synthesize(
            request.text,
            voice: request.voiceProfileName,
            rate: request.settings.rate * request.settings.speedMultiplier,
            volume: request.settings.volume,
            pitch: 1.0
        )

        outputMutex.wait()
        defer { outputMutex.signal() }

        output.removeAll(keepingCapacity: false)
        outputOffset = 0

        guard
            let audioBuffer,
            audioBuffer.frameLength > 0,
            let channelData = audioBuffer.floatChannelData
        else {
            return
        }

        let samples = UnsafeBufferPointer(
            start: channelData[0],
            count: Int(audioBuffer.frameLength)
        )
        output.append(contentsOf: samples)
    }

    public override func cancelSpeechRequest() {
        rhvoiceEngine.cancel()
        outputMutex.wait()
        output.removeAll(keepingCapacity: false)
        outputOffset = 0
        outputMutex.signal()
    }

    public override func messageChannel(for channelName: String) -> AUMessageChannel {
        final class MessageChannel: AUMessageChannel {
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
        return MessageChannel()
    }

    private func performRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
        renderEvents: UnsafePointer<AURenderEvent>?,
        renderPull: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        _ = timestamp
        _ = outputBusNumber
        _ = renderEvents
        _ = renderPull

        let audioBuffers = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        guard let data = audioBuffers[0].mData else {
            return kAudioUnitErr_InvalidParameter
        }

        let frames = data.assumingMemoryBound(to: Float.self)
        let requestedFrames = Int(frameCount)
        frames.update(repeating: 0, count: requestedFrames)
        audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
        audioBuffers[0].mNumberChannels = 1

        outputMutex.wait()
        defer { outputMutex.signal() }

        let availableCount = max(0, output.count - outputOffset)
        let count = min(availableCount, requestedFrames)

        if count > 0 {
            output.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                frames.update(from: baseAddress.advanced(by: outputOffset), count: count)
            }
            audioBuffers[0].mDataByteSize = UInt32(count * MemoryLayout<Float>.size)
            outputOffset += count
        }

        if outputOffset >= output.count {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            output.removeAll(keepingCapacity: false)
            outputOffset = 0
        } else if count > 0 {
            actionFlags.pointee = .offlineUnitRenderAction_Render
        } else {
            actionFlags.pointee = []
        }

        return noErr
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        performRender
    }

    private func resolvedRequest(
        for speechRequest: AVSpeechSynthesisProviderRequest
    ) -> RHVoiceSynthesisRequest {
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
        let identifier = speechRequest.voice.identifier

        guard snapshot.voiceCatalog.contains(where: { $0.identifier == identifier }) else {
            let fallback = RHVoiceSharedSettings.voiceCatalog.first {
                $0.identifier == identifier
            } ?? RHVoiceSharedSettings.voiceCatalog.first!
            return RHVoiceSynthesisRequest(
                text: speechRequest.ssmlRepresentation,
                voiceIdentifier: fallback.identifier,
                voiceProfileName: fallback.profileName,
                settings: RHVoiceSpeechSettings(
                    rate: Double(rateValue),
                    volume: Double(volumeValue),
                    speedMultiplier: Double(speedMultiplierValue),
                    sentencePause: Double(sentencePauseValue)
                ),
                source: .system
            )
        }

        return RHVoiceSynthesisRequestFactory.systemRequest(
            text: speechRequest.ssmlRepresentation,
            voiceIdentifier: identifier,
            snapshot: snapshot
        )
    }
}
