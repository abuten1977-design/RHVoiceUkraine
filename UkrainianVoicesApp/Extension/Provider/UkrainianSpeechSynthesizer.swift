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

            // Apply app speedMultiplier by modifying SSML prosody rate
            let finalText = Self.applySpeedMultiplier(
                to: request.text,
                multiplier: request.settings.speedMultiplier
            )

            self.rhvoiceEngine.synthesizeStreaming(
                finalText,
                voice: request.voiceProfileName,
                rate: request.settings.rate,
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

    /// Modify SSML prosody rate by multiplying with app speedMultiplier.
    /// VoiceOver sends rate="423.99997%", speedMultiplier=2.0 → final rate="500.00%", capped at 500%.
    private static func applySpeedMultiplier(to ssml: String, multiplier: Double) -> String {
        guard multiplier != 1.0 else {
            rhLog("SSML speed: multiplier=1.0, no change")
            return ssml
        }
        guard ssml.contains("rate=\"") else {
            rhLog("SSML speed: no prosody rate found")
            return ssml
        }

        // Match decimal and integer: rate="423.99997%" or rate="224%"
        let pattern = try? NSRegularExpression(pattern: #"rate="([0-9]+(?:\.[0-9]+)?)%""#)
        guard let match = pattern?.firstMatch(in: ssml, range: NSRange(ssml.startIndex..., in: ssml)),
              let valueRange = Range(match.range(at: 1), in: ssml),
              let originalRate = Double(ssml[valueRange]) else {
            rhLog("SSML speed: unparseable rate")
            return ssml
        }

        let finalRate = min(originalRate * multiplier, 500.0)
        let finalStr = String(format: "%.2f", finalRate)
        let result = (ssml as NSString).replacingCharacters(
            in: match.range,
            with: "rate=\"\(finalStr)%\""
        )
        rhLog("SSML speed: original=\(String(format: "%.2f", originalRate))% × multiplier=\(String(format: "%.2f", multiplier)) → final=\(finalStr)%")
        return result
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

        // VoiceOver controls rate/volume/pitch via SSML prosody.
        // App controls only speedMultiplier and sentencePause.
        // rate/volume/pitch passed as neutral (0.5/1.0/1.0) so buildMessage SSML branch stays neutral.
        NSLog("📊 VO final: speedMultiplier=%.2f sentencePause=%.2f, rate/volume/pitch controlled by SSML",
              base.speedMultiplier, base.sentencePause)

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
