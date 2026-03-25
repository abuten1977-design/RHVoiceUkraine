//
//  UkrainianSpeechSynthesizer.swift
//  UkrainianVoicesExtension
//
//  Copyright (C) 2026 Andriy Butenko
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Speech Synthesis Provider Extension for Ukrainian voices.
//  Uses RHVoice C library via Objective-C++ bridge (RHVoiceEngine).
//  Implements AVSpeechSynthesisProviderAudioUnit — required for VoiceOver integration.
//

import AVFoundation
import AudioToolbox

public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {

    // MARK: - Audio Unit setup

    private var outputBus: AUAudioUnitBus
    private var _outputBusses: AUAudioUnitBusArray!
    private let sampleRate = 24000.0
    private var format: AVAudioFormat

    @objc public override init(componentDescription: AudioComponentDescription,
                               options: AudioComponentInstantiationOptions) throws {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: sampleRate, channels: 1, interleaved: true)!
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        _outputBusses = AUAudioUnitBusArray(audioUnit: self,
                                            busType: .output, busses: [outputBus])
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }
    public override var canProcessInPlace: Bool { true }

    // MARK: - Audio buffer state

    private let outputQueue = DispatchQueue(label: "UkrainianSpeechSynthesizer.output",
                                            qos: .userInteractive)
    private var outputData: [Float] = []
    private var outputOffset = 0
    private var renderComplete = false

    // MARK: - Rendering
    // NOTE: Safe to use Swift — Speech Extensions process offline, not realtime.

    public override var internalRenderBlock: AUInternalRenderBlock { performRender }

    private func performRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputBusNumber: Int,
        outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
        renderEvents: UnsafePointer<AURenderEvent>?,
        renderPull: AURenderPullInputBlock?
    ) -> AUAudioUnitStatus {
        let intFrameCount = Int(frameCount)

        var available = 0
        var total = 0
        outputQueue.sync {
            total = outputData.count
            available = min(max(total - outputOffset, 0), intFrameCount)
        }

        // All data rendered — signal completion
        if renderComplete && available == 0 {
            actionFlags.pointee = .offlineUnitRenderAction_Complete
            return noErr
        }

        // Fill output buffer
        outputAudioBufferList.pointee.mNumberBuffers = 1
        var buf = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)[0]
        let frames = buf.mData!.assumingMemoryBound(to: Float32.self)
        frames.update(repeating: 0, count: intFrameCount)
        buf.mNumberChannels = 1
        buf.mDataByteSize = UInt32(available * MemoryLayout<Float32>.size)

        var slice: [Float] = []
        outputQueue.sync {
            if outputOffset >= 0 && outputOffset + available <= outputData.count {
                slice = Array(outputData[outputOffset..<(outputOffset + available)])
            }
        }
        for (i, sample) in slice.enumerated() { frames[i] = sample }
        outputOffset += available
        actionFlags.pointee = .offlineUnitRenderAction_Render
        return noErr
    }

    // MARK: - Speech synthesis

    private let engine = RHVoiceEngine()

    public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
        cancelSpeechRequest()

        let voiceName = speechRequest.voice.name
        // Extract plain text from SSML (strip tags)
        let ssml = speechRequest.ssmlRepresentation
        let text = ssml
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            outputQueue.sync { renderComplete = true }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let buffer = self.engine.synthesize(text, voice: voiceName,
                                                rate: 1.0, volume: 1.0, pitch: 1.0)
            self.outputQueue.sync {
                if let buf = buffer, let data = buf.floatChannelData?[0] {
                    let count = Int(buf.frameLength)
                    self.outputData = Array(UnsafeBufferPointer(start: data, count: count))
                }
                self.renderComplete = true
            }
        }
    }

    public override func cancelSpeechRequest() {
        outputQueue.sync {
            outputData = []
            outputOffset = 0
            renderComplete = false
        }
    }

    // MARK: - Voices

    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { ukrainianVoices }
        set { }
    }

    /// Ukrainian voices registered with the system.
    private var ukrainianVoices: [AVSpeechSynthesisProviderVoice] {
        return [
            AVSpeechSynthesisProviderVoice(name: "Anatol",
                identifier: "com.andriybutenko.RHVoiceUA.anatol",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]),
            AVSpeechSynthesisProviderVoice(name: "Marianna",
                identifier: "com.andriybutenko.RHVoiceUA.marianna",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]),
            AVSpeechSynthesisProviderVoice(name: "Natalia",
                identifier: "com.andriybutenko.RHVoiceUA.natalia",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]),
            AVSpeechSynthesisProviderVoice(name: "Volodymyr",
                identifier: "com.andriybutenko.RHVoiceUA.volodymyr",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"])
        ]
    }
}
