import AVFoundation
import AVFAudio
import CoreAudio
import CoreMedia
import Foundation
import RHVoiceKit

private func rhLog(_ msg: String) {
    msg.withCString { RHVoiceDebugLogString($0) }
}

@available(iOS 16.0, macOS 13.0, *)
@objc(UkrainianSpeechSynthesizer)
public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus

    // Simple buffer model (like eSpeak): flat array + read offset
    private var outputData: [Float] = []
    private var outputOffset: Int = 0
    private var synthesisComplete: Bool = true
    private let lock = NSLock()

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
        try super.allocateRenderResources()
        _ = self.rhvoiceEngine
    }

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            let enabled = Set(RHVoiceSharedSettingsStore.loadSnapshot().enabledVoiceIdentifiers)
            return Self.staticVoices.filter { enabled.contains($0.identifier) }
        }
        set { }
    }

    private var requestCounter: Int = 0

    // MARK: - Synthesize (sync, like eSpeak)

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let t0 = CFAbsoluteTimeGetCurrent()
        requestCounter += 1
        let reqId = requestCounter
        let request = resolvedRequest(for: speechRequest)

        rhLog("req#\(reqId) START voice=\(request.voiceProfileName) text=\(request.text.count) chars")

        // Extract rate and volume from SSML
        let ssmlRate = Self.extractSSMLRate(from: request.text)
        let ssmlVolume = Self.extractSSMLVolume(from: request.text)
        // Up to 2.0 — linear (slow→normal→fast). Above 2.0 — log curve (no sudden jump)
        let mappedRate = ssmlRate <= 2.0 ? ssmlRate : 2.0 + log(ssmlRate / 2.0) * 1.5
        let effectiveRate = mappedRate * request.settings.speedMultiplier
        let cappedRate = min(effectiveRate, 4.0)
        rhLog("req#\(reqId) ssmlRate=\(String(format: "%.2f", ssmlRate)) → mapped=\(String(format: "%.2f", mappedRate)) × mult=\(String(format: "%.2f", request.settings.speedMultiplier)) → rate=\(String(format: "%.2f", cappedRate)) vol=\(String(format: "%.2f", ssmlVolume))")

        // Synchronous synthesis — all audio ready before render starts
        guard let pcmBuffer = rhvoiceEngine.synthesize(
            request.text,
            voice: request.voiceProfileName,
            rate: cappedRate,
            volume: ssmlVolume,
            pitch: request.settings.pitch
        ) else {
            rhLog("req#\(reqId) synthesis FAILED")
            lock.lock()
            outputData = []
            outputOffset = 0
            synthesisComplete = true
            lock.unlock()
            return
        }

        // Convert PCM buffer to Float array
        let frameCount = Int(pcmBuffer.frameLength)
        guard let floatData = pcmBuffer.floatChannelData?[0] else {
            rhLog("req#\(reqId) no float data")
            lock.lock()
            outputData = []
            outputOffset = 0
            synthesisComplete = true
            lock.unlock()
            return
        }

        let tSynth = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        rhLog("req#\(reqId) synthesized \(frameCount) frames in \(String(format: "%.1f", tSynth)) ms")

        // Store for render
        lock.lock()
        outputData = Array(UnsafeBufferPointer(start: floatData, count: frameCount))
        outputOffset = 0
        synthesisComplete = false
        lock.unlock()
    }

    public override func cancelSpeechRequest() {
        rhLog("cancelSpeechRequest")
        rhvoiceEngine.cancel()
        lock.lock()
        outputData = []
        outputOffset = 0
        synthesisComplete = true
        lock.unlock()
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

    // MARK: - Render (simple array + offset, like eSpeak)

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

        // Zero-fill first
        frames.update(repeating: 0, count: requestedFrames)
        audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
        audioBuffers[0].mNumberChannels = 1

        lock.lock()
        let available = outputData.count - outputOffset
        let isComplete = synthesisComplete

        if available <= 0 {
            lock.unlock()
            if isComplete {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            } else {
                // Synthesis still running — send silence, keep pipeline
                actionFlags.pointee = .offlineUnitRenderAction_Render
            }
            return noErr
        }

        let toCopy = min(requestedFrames, available)
        outputData.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            frames.update(from: base.advanced(by: outputOffset), count: toCopy)
        }
        outputOffset += toCopy
        let done = outputOffset >= outputData.count
        lock.unlock()

        if done {
            // Fade out last 128 samples to avoid click
            let fadeLen = min(toCopy, 128)
            if fadeLen > 0 {
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
                rate:            0.5,
                volume:          1.0,
                speedMultiplier: base.speedMultiplier,
                sentencePause:   base.sentencePause,
                pitch:           1.0
            ),
            source: .system
        )
    }
}
