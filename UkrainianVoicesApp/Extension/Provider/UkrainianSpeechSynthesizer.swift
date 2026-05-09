import AVFoundation
import AVFAudio
import CoreAudio
import CoreMedia
import Foundation
import RHVoiceBridge

private func rhLog(_ msg: String) {
    msg.withCString { RHVoiceDebugLogString($0) }
}

@available(iOS 16.0, macOS 13.0, *)
@objc(UkrainianSpeechSynthesizer)
public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus

    // Synchronous model (like eSpeak): flat array + read offset
    private var outputData: [Float] = []
    private var outputOffset: Int = 0
    private let condition = NSCondition()
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

    private var outputBussesStorage: AUAudioUnitBusArray!

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
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBussesStorage
    }

    public override func allocateRenderResources() throws {
        rhLog("allocateRenderResources: START")
        try super.allocateRenderResources()
        let engine = self.rhvoiceEngine
        rhLog("allocateRenderResources: engine ready")
    }

    // Always return ALL voices (like eSpeak) — iOS caches the list
    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { Self.staticVoices }
        set { }
    }

    private var requestCounter: Int = 0

    // MARK: - Synthesize (synchronous, like eSpeak)

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        requestCounter += 1
        let reqId = requestCounter
        let request = resolvedRequest(for: speechRequest)

        rhLog("req#\(reqId) START voice=\(request.voiceProfileName) text=\(request.text.count) chars")

        let ssmlRate = Self.extractSSMLRate(from: request.text)
        let ssmlVolume = Self.extractSSMLVolume(from: request.text)
        let mappedRate = ssmlRate <= 2.0 ? ssmlRate : 2.0 + log(ssmlRate / 2.0) * 1.5
        let effectiveRate = mappedRate * request.settings.speedMultiplier
        let cappedRate = min(effectiveRate, 4.0)
        let effectiveVolume = ssmlVolume * request.settings.volume

        rhLog("req#\(reqId) ssmlRate=\(String(format: "%.2f", ssmlRate)) → rate=\(String(format: "%.2f", cappedRate)) vol=\(String(format: "%.2f", effectiveVolume))")

        condition.lock()
        isSynthesizing = true
        outputData = []
        outputOffset = 0
        condition.unlock()

        // Synchronous synthesis — all audio ready before render starts
        let pcmBuffer = rhvoiceEngine.synthesize(
            request.text,
            voice: request.voiceProfileName,
            rate: cappedRate,
            volume: effectiveVolume,
            pitch: request.settings.pitch
        )

        condition.lock()
        defer {
            isSynthesizing = false
            condition.broadcast()
            condition.unlock()
            rhLog("req#\(reqId) FINISHED synthesizing state")
        }

        guard let buffer = pcmBuffer,
              let floatData = buffer.floatChannelData?[0] else {
            rhLog("req#\(reqId) synthesis FAILED or no data")
            outputData = []
            outputOffset = 0
            return
        }

        let frameCount = Int(buffer.frameLength)
        rhLog("req#\(reqId) synthesized \(frameCount) frames")
        outputData = Array(UnsafeBufferPointer(start: floatData, count: frameCount))
        outputOffset = 0
    }

    public override func cancelSpeechRequest() {
        rhLog("cancelSpeechRequest")
        rhvoiceEngine.cancel()
        condition.lock()
        isSynthesizing = false
        outputData.removeAll()
        outputOffset = 0
        condition.broadcast()
        condition.unlock()
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

    // MARK: - Render (like eSpeak: simple array + offset)

    private func performRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
        renderEvents: UnsafePointer<AURenderEvent>?,
        renderPull: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        let audioBuffers = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
        guard let data = audioBuffers[0].mData else {
            return kAudioUnitErr_InvalidParameter
        }

        let frames = data.assumingMemoryBound(to: Float.self)
        let requestedFrames = Int(frameCount)

        frames.update(repeating: 0, count: requestedFrames)
        audioBuffers[0].mNumberChannels = 1

        condition.lock()
        
        if (outputData.count - outputOffset) <= 0 && isSynthesizing {
            // Data not ready yet — return silence, iOS will call render again in ~10ms
            condition.unlock()
            audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
            actionFlags.pointee = .offlineUnitRenderAction_Render
            return noErr
        }

        let available = outputData.count - outputOffset

        if available <= 0 {
            let synthesizing = isSynthesizing
            condition.unlock()
            audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
            if synthesizing {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            }
            return noErr
        }

        let toCopy = min(requestedFrames, available)
        outputData.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            frames.update(from: base.advanced(by: outputOffset), count: toCopy)
        }
        outputOffset += toCopy
        let done = (outputOffset >= outputData.count) && !isSynthesizing
        if done {
            outputData.removeAll()
        }
        condition.unlock()

        audioBuffers[0].mDataByteSize = UInt32(toCopy * MemoryLayout<Float>.size)

        if done {
            let fadeLen = min(32, toCopy / 4)
            if fadeLen > 0 && toCopy > 256 {
                for i in 0..<fadeLen {
                    frames[toCopy - fadeLen + i] *= Float(fadeLen - 1 - i) / Float(fadeLen)
                }
            }
            actionFlags.pointee = .offlineUnitRenderAction_Complete
        } else {
            actionFlags.pointee = .offlineUnitRenderAction_Render
        }

        return noErr
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        performRender
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

    // MARK: - Resolve request

    private func resolvedRequest(
        for speechRequest: AVSpeechSynthesisProviderRequest
    ) -> RHVoiceSynthesisRequest {
        let identifier = speechRequest.voice.identifier
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()

        let descriptor = snapshot.voiceCatalog.first { $0.identifier == identifier }
            ?? RHVoiceSharedSettings.voiceCatalog.first!

        let base = snapshot.effectiveSettings(for: descriptor.identifier)

        rhLog("voice.id: \(identifier) voice.name: \(speechRequest.voice.name)")
        let ssmlPreview = String(speechRequest.ssmlRepresentation.prefix(300))
        rhLog("ssml: \(ssmlPreview)")

        return RHVoiceSynthesisRequest(
            text: speechRequest.ssmlRepresentation,
            voiceIdentifier: descriptor.identifier,
            voiceProfileName: descriptor.profileName,
            settings: RHVoiceSpeechSettings(
                rate:            base.rate,
                volume:          base.volume,
                speedMultiplier: base.speedMultiplier,
                sentencePause:   base.sentencePause,
                pitch:           base.pitch
            ),
            source: .system
        )
    }
}
