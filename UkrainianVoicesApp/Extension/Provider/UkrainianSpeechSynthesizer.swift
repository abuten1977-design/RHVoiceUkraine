//
//  UkrainianSpeechSynthesizer.swift
//  Ukrainian Voices Extension
//

import AVFoundation
import AVFAudio
import CoreAudio

@available(iOS 16.0, *)
@objc(UkrainianSpeechSynthesizer)
public class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {

    // MARK: - Audio setup

    private var outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!

    // MARK: - Synthesis state

    private let rhvoiceEngine: RHVoiceEngine
    private let audioBuffer = RHVoiceAudioBuffer()

    // Pre-buffer threshold: 100ms at 24kHz = 2400 frames
    private let preBufferFrames: Int = 2400

    // MARK: - Settings

    private let appGroup = "group.rhvoice.UkrainianVoices.shared"
    private let defaults: UserDefaults?
    private var _speechVoices: [AVSpeechSynthesisProviderVoice] = []

    // MARK: - Init

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        self.rhvoiceEngine = RHVoiceEngine()
        self.defaults = UserDefaults(suiteName: appGroup)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 24000.0,
                                   channels: 1,
                                   interleaved: true)!
        self.outputBus = try AUAudioUnitBus(format: format)

        try super.init(componentDescription: componentDescription, options: options)

        _outputBusses = AUAudioUnitBusArray(audioUnit: self,
                                            busType: .output,
                                            busses: [outputBus])

        _speechVoices = [
            AVSpeechSynthesisProviderVoice(name: "Anatol",
                identifier: "com.rhvoice.UkrainianVoices.anatol",
                primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
            AVSpeechSynthesisProviderVoice(name: "Natalia",
                identifier: "com.rhvoice.UkrainianVoices.natalia",
                primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
            AVSpeechSynthesisProviderVoice(name: "Marianna",
                identifier: "com.rhvoice.UkrainianVoices.marianna",
                primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
            AVSpeechSynthesisProviderVoice(name: "Volodymyr",
                identifier: "com.rhvoice.UkrainianVoices.volodymyr",
                primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"])
        ]
    }

    public override var outputBusses: AUAudioUnitBusArray {
        return _outputBusses
    }

    // MARK: - Voice list

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            guard let enabledIds = defaults?.stringArray(forKey: "enabledVoiceIdentifiers"),
                  !enabledIds.isEmpty else {
                return _speechVoices
            }
            return _speechVoices.filter { enabledIds.contains($0.identifier) }
        }
        set { _speechVoices = newValue }
    }

    // MARK: - Synthesis request

    public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
        let voiceName = request.voice.identifier.components(separatedBy: ".").last ?? "anatol"
        // Use object(forKey:) to distinguish "not set" (nil) from explicit 0.0
        let rate = (defaults?.object(forKey: "rate") as? Double) ?? 0.5
        let volume = (defaults?.object(forKey: "volume") as? Double) ?? 1.0
        let speedMultiplier = (defaults?.object(forKey: "speedMultiplier") as? Double) ?? 1.0
        let text = request.ssmlRepresentation

        // Cancel any previous request first, then begin new one
        rhvoiceEngine.cancel()
        let requestToken = audioBuffer.beginRequest()

        NSLog("🎤 Synthesis: voice=\(voiceName) rate=\(rate * speedMultiplier)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.rhvoiceEngine.synthesizeStreaming(
                text,
                voice: voiceName,
                rate: rate * speedMultiplier,
                volume: volume,
                pitch: 1.0
            ) { samples, count, sampleRate in
                _ = sampleRate
                self.audioBuffer.appendSamples(samples, count: count, token: requestToken)
            }

            self.audioBuffer.markCompleted(with: requestToken)

            NSLog("✅ Synthesis complete")
        }
    }

    public override func cancelSpeechRequest() {
        audioBuffer.cancelCurrentRequest()
        rhvoiceEngine.cancel()
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
