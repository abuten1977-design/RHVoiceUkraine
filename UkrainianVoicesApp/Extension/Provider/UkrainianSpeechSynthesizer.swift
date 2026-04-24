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
    private let rhvoiceEngine: RHVoiceEngine
    private let outputBus: AUAudioUnitBus
    private let outputMutex = DispatchSemaphore(value: 1)
    private let availableVoices: [AVSpeechSynthesisProviderVoice]

    private var outputBussesStorage: AUAudioUnitBusArray!
    private var output: [Float] = []
    private var outputOffset = 0

    private var rateValue: AUValue
    private var volumeValue: AUValue
    private var speedMultiplierValue: AUValue
    private var sentencePauseValue: AUValue

    @objc
    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        let settings = RHVoiceSpeechSettings.recommended
        self.rhvoiceEngine = RHVoiceEngine()
        self.rateValue = AUValue(settings.rate)
        self.volumeValue = AUValue(settings.volume)
        self.speedMultiplierValue = AUValue(settings.speedMultiplier)
        self.sentencePauseValue = AUValue(settings.sentencePause)

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
        self.availableVoices = RHVoiceSharedSettings.voiceCatalog.map {
            AVSpeechSynthesisProviderVoice(
                name: $0.name,
                identifier: $0.identifier,
                primaryLanguages: [$0.language],
                supportedLanguages: [$0.language]
            )
        }

        try super.init(componentDescription: componentDescription, options: options)

        self.outputBussesStorage = AUAudioUnitBusArray(
            audioUnit: self,
            busType: .output,
            busses: [outputBus]
        )

        let parameterTree = AUParameterTree.createTree(withChildren: [
            AUParameterTree.createGroup(
                withIdentifier: "rhvoice",
                name: "RHVoice",
                children: [
                    AUParameterTree.createParameter(
                        withIdentifier: "rate",
                        name: "Rate",
                        address: RHVoiceParameter.rate.rawValue,
                        min: 0.1,
                        max: 2.0,
                        unit: .rate,
                        unitName: nil,
                        valueStrings: nil,
                        dependentParameters: nil
                    ),
                    AUParameterTree.createParameter(
                        withIdentifier: "volume",
                        name: "Volume",
                        address: RHVoiceParameter.volume.rawValue,
                        min: 0.0,
                        max: 1.0,
                        unit: .linearGain,
                        unitName: nil,
                        valueStrings: nil,
                        dependentParameters: nil
                    ),
                    AUParameterTree.createParameter(
                        withIdentifier: "speedMultiplier",
                        name: "Speed Multiplier",
                        address: RHVoiceParameter.speedMultiplier.rawValue,
                        min: 0.5,
                        max: 5.0,
                        unit: .ratio,
                        unitName: nil,
                        valueStrings: nil,
                        dependentParameters: nil
                    ),
                    AUParameterTree.createParameter(
                        withIdentifier: "sentencePause",
                        name: "Sentence Pause",
                        address: RHVoiceParameter.sentencePause.rawValue,
                        min: 0.0,
                        max: 2000.0,
                        unit: .milliseconds,
                        unitName: nil,
                        valueStrings: nil,
                        dependentParameters: nil
                    )
                ]
            )
        ])
        parameterTree.implementorValueProvider = { [weak self] parameter in
            guard let self else { return 0 }
            switch parameter.address {
            case RHVoiceParameter.rate.rawValue:
                return self.rateValue
            case RHVoiceParameter.volume.rawValue:
                return self.volumeValue
            case RHVoiceParameter.speedMultiplier.rawValue:
                return self.speedMultiplierValue
            case RHVoiceParameter.sentencePause.rawValue:
                return self.sentencePauseValue
            default:
                return 0
            }
        }
        parameterTree.implementorValueObserver = { [weak self] parameter, value in
            guard let self else { return }
            switch parameter.address {
            case RHVoiceParameter.rate.rawValue:
                self.rateValue = value
            case RHVoiceParameter.volume.rawValue:
                self.volumeValue = value
            case RHVoiceParameter.speedMultiplier.rawValue:
                self.speedMultiplierValue = value
            case RHVoiceParameter.sentencePause.rawValue:
                self.sentencePauseValue = value
            default:
                break
            }
        }
        for parameter in parameterTree.allParameters where parameter.unit != .indexed {
            parameter.value = parameterTree.implementorValueProvider?(parameter) ?? 0
        }
        self.parameterTree = parameterTree
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBussesStorage
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
    }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { availableVoices }
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
            private let voices: [RHVoiceVoiceDescriptor]

            init(voices: [RHVoiceVoiceDescriptor]) {
                self.voices = voices
            }

            func callAudioUnit(_ message: [AnyHashable : Any]) -> [AnyHashable : Any] {
                var response: [AnyHashable: Any] = [:]

                if message["initHost"] as? Bool == true {
                    response["voiceIds"] = voices.map(\.identifier)
                    response["voiceNames"] = voices.map(\.name)
                    response["primaryLanguages"] = voices.map(\.language)
                }

                return response
            }
        }

        _ = channelName
        return MessageChannel(voices: RHVoiceSharedSettings.voiceCatalog)
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
        frames.assign(repeating: 0, count: requestedFrames)
        audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
        audioBuffers[0].mNumberChannels = 1

        outputMutex.wait()
        defer { outputMutex.signal() }

        let availableCount = max(0, output.count - outputOffset)
        let count = min(availableCount, requestedFrames)

        if count > 0 {
            output.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                frames.assign(from: baseAddress.advanced(by: outputOffset), count: count)
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
