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
    private var outputData: [Float] = []
    private var outputOffset = 0
    private var synthesisCompleted = false
    private let outputDataQueue = DispatchQueue(label: "com.rhvoice.ukrainian.output", qos: .userInteractive)

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

    // MARK: - outputBusses (обов'язковий override)

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

        // Скидаємо стан
        outputDataQueue.sync {
            self.outputData = []
            self.outputOffset = 0
            self.synthesisCompleted = false
        }

        NSLog("🎤 Synthesis: voice=\(voiceName) rate=\(rate * speedMultiplier)")

        // Синтез в background — chunks надходять через callback
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.rhvoiceEngine.synthesizeStreaming(
                text,
                voice: voiceName,
                rate: rate * speedMultiplier,
                volume: volume,
                pitch: 1.0
            ) { samples, count, sampleRate in
                // Конвертуємо Int16 → Float32 і додаємо в outputData
                var floats = [Float](repeating: 0, count: Int(count))
                for i in 0..<Int(count) {
                    floats[i] = Float(samples[i]) / 32768.0
                }
                self.outputDataQueue.sync {
                    self.outputData.append(contentsOf: floats)
                }
            }

            // Синтез завершено
            self.outputDataQueue.sync {
                self.synthesisCompleted = true
            }
            NSLog("✅ Synthesis complete: \(self.outputData.count) frames")
        }
    }

    public override func cancelSpeechRequest() {
        rhvoiceEngine.cancel()
        outputDataQueue.sync {
            outputData = []
            outputOffset = 0
            synthesisCompleted = true
        }
    }

    // MARK: - Render block

    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] (actionFlags, timestamp, frameCount, outputBusNumber,
                              outputAudioBufferList, renderEvents, pullInputBlock) in
            guard let self = self else { return kAudioUnitErr_NoConnection }

            let intFrameCount = Int(frameCount)
            var frames: [Float] = []
            var completed = false

            self.outputDataQueue.sync {
                let available = max(self.outputData.count - self.outputOffset, 0)
                let toCopy = min(available, intFrameCount)
                if toCopy > 0 {
                    let start = self.outputOffset
                    frames = Array(self.outputData[start..<(start + toCopy)])
                    self.outputOffset += toCopy
                }
                let remaining = max(self.outputData.count - self.outputOffset, 0)
                completed = self.synthesisCompleted && remaining == 0
            }

            // Записуємо в output buffer
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            if let mData = ablPointer[0].mData {
                let outFrames = mData.assumingMemoryBound(to: Float32.self)
                // Спочатку заповнюємо тишею
                outFrames.update(repeating: 0, count: intFrameCount)
                // Потім записуємо дані
                for (i, f) in frames.enumerated() {
                    outFrames[i] = f
                }
                ablPointer[0].mDataByteSize = UInt32(intFrameCount * MemoryLayout<Float32>.size)
                ablPointer[0].mNumberChannels = 1
            }

            if completed {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            }

            return noErr
        }
    }
}
