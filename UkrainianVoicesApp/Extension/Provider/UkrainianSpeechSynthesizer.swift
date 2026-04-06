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
    // All fields accessed from render block use os_unfair_lock — the only lock
    // safe for real-time audio threads (no priority inversion, no blocking).

    private let rhvoiceEngine: RHVoiceEngine

    // Protected by unfairLock — render thread reads, background thread writes
    private var outputData: [Float] = []
    private var outputOffset: Int = 0
    private var synthesisCompleted: Bool = false
    private var unfairLock = os_unfair_lock()

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
        let rate = defaults?.double(forKey: "rate") ?? 0.5
        let volume = defaults?.double(forKey: "volume") ?? 1.0
        let speedMultiplier = defaults?.double(forKey: "speedMultiplier") ?? 1.0
        let text = request.ssmlRepresentation

        // Reset state — called on non-render thread, safe to lock briefly
        os_unfair_lock_lock(&unfairLock)
        outputData = []
        outputOffset = 0
        synthesisCompleted = false
        os_unfair_lock_unlock(&unfairLock)

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
                var floats = [Float](repeating: 0, count: Int(count))
                for i in 0..<Int(count) {
                    floats[i] = Float(samples[i]) / 32768.0
                }
                os_unfair_lock_lock(&self.unfairLock)
                self.outputData.append(contentsOf: floats)
                os_unfair_lock_unlock(&self.unfairLock)
            }

            os_unfair_lock_lock(&self.unfairLock)
            self.synthesisCompleted = true
            os_unfair_lock_unlock(&self.unfairLock)

            NSLog("✅ Synthesis complete: \(self.outputData.count) frames")
        }
    }

    public override func cancelSpeechRequest() {
        rhvoiceEngine.cancel()
        os_unfair_lock_lock(&unfairLock)
        outputData = []
        outputOffset = 0
        synthesisCompleted = true
        os_unfair_lock_unlock(&unfairLock)
    }

    // MARK: - Render block
    // RULES:
    // 1. NO DispatchQueue.sync/async — forbidden in real-time thread
    // 2. NO usleep, semaphore, mutex — forbidden in real-time thread
    // 3. os_unfair_lock is safe: non-blocking trylock pattern, or brief lock
    //    since background thread holds it only for array append (microseconds)
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

            // Lock is held only for array read — background thread holds it
            // only during append (microseconds). This is safe for real-time.
            os_unfair_lock_lock(&self.unfairLock)
            let totalFrames = self.outputData.count
            let offset = self.outputOffset
            let done = self.synthesisCompleted
            os_unfair_lock_unlock(&self.unfairLock)

            let available = max(totalFrames - offset, 0)

            // Pre-buffer: wait until 100ms accumulated OR synthesis is done
            if available == 0 {
                if done {
                    actionFlags.pointee = .offlineUnitRenderAction_Complete
                }
                // else: return silence, VoiceOver will call again
                return noErr
            }

            // Not enough pre-buffered yet — return silence and wait
            if available < self.preBufferFrames && !done {
                return noErr
            }

            // Copy frames to output
            let toCopy = min(available, intFrameCount)
            os_unfair_lock_lock(&self.unfairLock)
            let currentOffset = self.outputOffset
            let currentTotal = self.outputData.count
            let actualCopy = min(currentTotal - currentOffset, intFrameCount)
            if actualCopy > 0 {
                self.outputData.withUnsafeBufferPointer { ptr in
                    outFrames.update(from: ptr.baseAddress! + currentOffset, count: actualCopy)
                }
                self.outputOffset += actualCopy
            }
            let remaining = self.outputData.count - self.outputOffset
            let completed = self.synthesisCompleted && remaining == 0
            os_unfair_lock_unlock(&self.unfairLock)

            if completed {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            }

            return noErr
        }
    }
}
