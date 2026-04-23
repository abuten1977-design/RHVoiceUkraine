//
//  UkrainianSpeechSynthesizer.swift
//  Ukrainian Voices Extension
//

import AVFoundation
import AVFAudio
import CoreAudio
import RHVoiceKit

@available(iOS 16.0, macOS 13.0, *)
@objc(UkrainianSpeechSynthesizer)
public class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {

    // MARK: - Audio setup

    private var outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!

    // MARK: - Synthesis state

    private let rhvoiceEngine: RHVoiceEngine
    private let audioBuffer = RHVoiceAudioBuffer()
    private let runtimeCoordinator = RHVoiceRuntimeCoordinator()

    // Pre-buffer threshold: 100ms at 24kHz = 2400 frames
    private let preBufferFrames: Int = 2400

    // MARK: - Settings

    private var _speechVoices: [AVSpeechSynthesisProviderVoice] = []

    // MARK: - Init

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        self.rhvoiceEngine = RHVoiceEngine()

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 24000.0,
                                   channels: 1,
                                   interleaved: true)!
        self.outputBus = try AUAudioUnitBus(format: format)

        try super.init(componentDescription: componentDescription, options: options)

        _outputBusses = AUAudioUnitBusArray(audioUnit: self,
                                            busType: .output,
                                            busses: [outputBus])

        _speechVoices = RHVoiceSharedSettings.voiceCatalog.map {
            AVSpeechSynthesisProviderVoice(
                name: $0.name,
                identifier: $0.identifier,
                primaryLanguages: [$0.language],
                supportedLanguages: [$0.language]
            )
        }
    }

    public override var outputBusses: AUAudioUnitBusArray {
        return _outputBusses
    }

    // MARK: - Voice list

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
            let enabledIds = snapshot.enabledVoiceIdentifiers
            guard !enabledIds.isEmpty else {
                return _speechVoices
            }
            return _speechVoices.filter { enabledIds.contains($0.identifier) }
        }
        set { _speechVoices = newValue }
    }

    // MARK: - Synthesis request

    public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
        let snapshot = RHVoiceSharedSettingsStore.loadSnapshot()
        let synthesisRequest = RHVoiceSynthesisRequestFactory.systemRequest(
            text: request.ssmlRepresentation,
            voiceIdentifier: request.voice.identifier,
            snapshot: snapshot
        )
        let runtimeToken = runtimeCoordinator.begin(synthesisRequest)

        // Cancel any previous request first, then begin new one
        rhvoiceEngine.cancel()
        let requestToken = audioBuffer.beginRequest()

        NSLog("🎤 Synthesis: voice=\(synthesisRequest.voiceProfileName) rate=\(synthesisRequest.settings.rate * synthesisRequest.settings.speedMultiplier)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.rhvoiceEngine.synthesizeStreaming(
                synthesisRequest.text,
                voice: synthesisRequest.voiceProfileName,
                rate: synthesisRequest.settings.rate * synthesisRequest.settings.speedMultiplier,
                volume: synthesisRequest.settings.volume,
                pitch: 1.0
            ) { samples, count, sampleRate in
                _ = sampleRate
                guard self.runtimeCoordinator.isCurrent(runtimeToken) else { return }
                self.audioBuffer.appendSamples(samples, count: count, token: requestToken)
            }

            if self.runtimeCoordinator.isCurrent(runtimeToken) {
                self.audioBuffer.markCompleted(with: requestToken)
                self.runtimeCoordinator.markCompleted(runtimeToken)
            }

            NSLog("✅ Synthesis complete")
        }
    }

    public override func cancelSpeechRequest() {
        let runtimeToken = runtimeCoordinator.beginCancel()
        audioBuffer.cancelCurrentRequest()
        rhvoiceEngine.cancel()
        if let runtimeToken {
            runtimeCoordinator.markCancelled(runtimeToken)
        }
    }

    // MARK: - Render block
    // RULES:
    // 1. NO DispatchQueue.sync/async — forbidden in real-time thread
    // 2. NO usleep, semaphore, mutex — forbidden in real-time thread
    // 3. Render consumes from an atomic request buffer with no shared Swift array
    // 4. If no data: return silence immediately

    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] (actionFlags, timestamp, frameCount, outputBusNumber,
                              outputAudioBufferList, renderEvents, pullInputBlock) in
            guard let self = self else { return kAudioUnitErr_NoConnection }

            let intFrameCount = Int(frameCount)
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)

            guard let mData = ablPointer[0].mData else { return kAudioUnitErr_InvalidParameter }
            let outFrames = mData.assumingMemoryBound(to: Float32.self)

            // Always zero-fill first — guarantees silence if we return early
            outFrames.update(repeating: 0, count: intFrameCount)
            ablPointer[0].mDataByteSize = UInt32(intFrameCount * MemoryLayout<Float32>.size)
            ablPointer[0].mNumberChannels = 1

            var completed = ObjCBool(false)
            let rendered = self.audioBuffer.renderFrames(
                outFrames,
                maxFrames: UInt(intFrameCount),
                preBufferFrames: UInt(self.preBufferFrames),
                didComplete: &completed
            )

            if completed.boolValue {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            } else if rendered {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            } else {
                // No data or pre-buffer not ready yet — return silence.
                actionFlags.pointee = []
            }

            return noErr
        }
    }
}
