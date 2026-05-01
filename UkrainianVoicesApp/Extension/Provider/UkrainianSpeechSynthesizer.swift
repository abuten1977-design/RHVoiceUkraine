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
    // Engine is lazy — created only when synthesis is actually requested.
    // This keeps init() lightweight for macOS component discovery (auval).
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus

    // Lock-free audio buffer — replaces DispatchSemaphore + [Float] array
    private let audioBuffer = RHVoiceAudioBuffer()
    private let preBufferFrames: Int = 1200 // 50ms at 24kHz

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

    // AU parameter values removed — settings come only from App Group snapshot.
    // Having AUValue properties here caused VoiceOver to expose numeric parameters
    // in quick settings (VO+Cmd+Shift+arrows showed percentages instead of voices).

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

        // No AUParameterTree — settings come from App Group snapshot.
        // Having rate/volume/pitch parameters here breaks VoiceOver quick settings
        // (VO+Cmd+Shift+arrows shows numbers instead of language/voice selection).
    }

    public override var outputBusses: AUAudioUnitBusArray {
        outputBussesStorage
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        // Warm up the engine to avoid lazy initialization delay during the first speech request
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

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        let t0 = CFAbsoluteTimeGetCurrent()
        requestCounter += 1
        let reqId = requestCounter
        let request = resolvedRequest(for: speechRequest)

        rhLog("req#\(reqId) START voice=\(request.voiceProfileName) rate=\(String(format: "%.2f", request.settings.rate)) vol=\(String(format: "%.2f", request.settings.volume)) pitch=\(String(format: "%.2f", request.settings.pitch)) text=\(request.text.count) chars")
        NSLog("[RHVOICE_TIMING] req#%d START voice=%@ rate=%.2f vol=%.2f pitch=%.2f text=%d chars",
              reqId, request.voiceProfileName, request.settings.rate, request.settings.volume,
              request.settings.pitch, request.text.count)

        rhvoiceEngine.cancel()
        let tCancel = (CFAbsoluteTimeGetCurrent()-t0)*1000
        NSLog("[RHVOICE_TIMING] req#%d cancel done: %.1f ms", reqId, tCancel)
        rhLog("req#\(reqId) cancel done: \(String(format: "%.1f", tCancel)) ms")

        let requestToken = audioBuffer.beginRequest()
        let tBegin = (CFAbsoluteTimeGetCurrent()-t0)*1000
        NSLog("[RHVOICE_TIMING] req#%d beginRequest: %.1f ms", reqId, tBegin)
        rhLog("req#\(reqId) beginRequest: \(String(format: "%.1f", tBegin)) ms")

        var firstChunk = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let tStream = CFAbsoluteTimeGetCurrent()
            let tStreamMs = (tStream-t0)*1000
            NSLog("[RHVOICE_TIMING] req#%d streaming start: %.1f ms from request", reqId, tStreamMs)
            rhLog("req#\(reqId) streaming start: \(String(format: "%.1f", tStreamMs)) ms")

            self.rhvoiceEngine.synthesizeStreaming(
                request.text,
                voice: request.voiceProfileName,
                rate: request.settings.rate * request.settings.speedMultiplier,
                volume: request.settings.volume,
                pitch: request.settings.pitch
            ) { samples, count, _ in
                if firstChunk {
                    firstChunk = false
                    let tChunk = (CFAbsoluteTimeGetCurrent()-t0)*1000
                    NSLog("[RHVOICE_TIMING] req#%d first chunk: %.1f ms from request, %u samples",
                          reqId, tChunk, count)
                    rhLog("req#\(reqId) first chunk: \(String(format: "%.1f", tChunk)) ms, \(count) samples")
                }
                self.audioBuffer.appendSamples(samples, count: count, token: requestToken)
            }

            self.audioBuffer.markCompleted(with: requestToken)
            let tDone = (CFAbsoluteTimeGetCurrent()-t0)*1000
            NSLog("[RHVOICE_TIMING] req#%d completed: %.1f ms from request", reqId, tDone)
            rhLog("req#\(reqId) completed: \(String(format: "%.1f", tDone)) ms")
        }
    }

    public override func cancelSpeechRequest() {
        audioBuffer.cancelCurrentRequest()
        rhvoiceEngine.cancel()
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

    // MARK: - Render (lock-free, no semaphore, no mutex, no usleep)

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

        // Zero-fill guarantees silence if renderFrames returns no data
        frames.update(repeating: 0, count: requestedFrames)
        audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
        audioBuffers[0].mNumberChannels = 1

        var completed = ObjCBool(false)
        let rendered = audioBuffer.renderFrames(
            frames,
            maxFrames: UInt(requestedFrames),
            preBufferFrames: UInt(preBufferFrames),
            didComplete: &completed
        )

        if completed.boolValue {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
        } else if rendered {
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
        let identifier = speechRequest.voice.identifier
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()

        let descriptor = snapshot.voiceCatalog.first { $0.identifier == identifier }
            ?? RHVoiceSharedSettings.voiceCatalog.first!

        let base = snapshot.effectiveSettings(for: descriptor.identifier)

        rhLog("voice.id: \(identifier) voice.name: \(speechRequest.voice.name)")
        let ssmlPreview = String(speechRequest.ssmlRepresentation.prefix(300))
        rhLog("ssml: \(ssmlPreview)")
        rhLog("snapshot rev=\(snapshot.revision) updated=\(snapshot.updatedAt)")

        NSLog("📊 SNAPSHOT base.rate=%.2f base.volume=%.2f base.pitch=%.2f",
              base.rate, base.volume, base.pitch)

        rhLog("final: rate=\(String(format: "%.2f", base.rate)) vol=\(String(format: "%.2f", base.volume)) pitch=\(String(format: "%.2f", base.pitch))")

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
