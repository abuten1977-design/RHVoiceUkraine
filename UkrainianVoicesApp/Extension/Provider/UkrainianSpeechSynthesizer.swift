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

    // MARK: - Audio setup (required by iOS)

    private var outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!
    private let sampleRate = 24000.0

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

        NSLog("✅ UkrainianSpeechSynthesizer initialized")
    }

    // MARK: - Required outputBusses override

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
        NSLog("🎤 Synthesis request: \(request.voice.identifier)")

        let rate = defaults?.double(forKey: "rate") ?? 0.5
        let volume = defaults?.double(forKey: "volume") ?? 1.0
        let speedMultiplier = defaults?.double(forKey: "speedMultiplier") ?? 1.0
        let finalRate = rate * speedMultiplier

        let voiceName = request.voice.identifier.components(separatedBy: ".").last ?? "anatol"
        let text = request.ssmlRepresentation

        // Синтез синхронно — щоб дані були готові до першого renderBlock
        if let buffer = rhvoiceEngine.synthesize(text, voice: voiceName,
                                                  rate: finalRate, volume: volume, pitch: 1.0),
           let channelData = buffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            var frames = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                frames[i] = channelData[0][i]
            }
            outputDataQueue.sync {
                self.outputData = frames
                self.outputOffset = 0
                self.synthesisCompleted = false
            }
            NSLog("✅ Synthesis done: \(frameCount) frames")
        } else {
            NSLog("❌ Synthesis failed")
            outputDataQueue.sync {
                self.outputData = []
                self.outputOffset = 0
                self.synthesisCompleted = true
            }
        }
    }

    public override func cancelSpeechRequest() {
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
            var remaining = 0
            var completed = false

            self.outputDataQueue.sync {
                let available = max(self.outputData.count - self.outputOffset, 0)
                let toCopy = min(available, intFrameCount)
                if toCopy > 0 {
                    frames = Array(self.outputData[self.outputOffset..<(self.outputOffset + toCopy)])
                    self.outputOffset += toCopy
                }
                remaining = max(self.outputData.count - self.outputOffset, 0)
                completed = remaining == 0
            }

            // Записуємо в output buffer
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            if let mData = ablPointer[0].mData {
                let outFrames = mData.assumingMemoryBound(to: Float32.self)
                outFrames.update(repeating: 0, count: intFrameCount)
                for (i, f) in frames.enumerated() {
                    outFrames[i] = f
                }
                ablPointer[0].mDataByteSize = UInt32(frames.count * MemoryLayout<Float32>.size)
                ablPointer[0].mNumberChannels = 1
            }

            if completed {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
                NSLog("🏁 Render complete")
            } else {
                actionFlags.pointee = .offlineUnitRenderAction_Render
            }

            return noErr
        }
    }
}
