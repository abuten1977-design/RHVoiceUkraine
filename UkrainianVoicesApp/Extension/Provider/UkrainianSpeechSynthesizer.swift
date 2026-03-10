//
//  UkrainianSpeechSynthesizer.swift
//  Ukrainian Voices Extension
//
//  РЕАЛЬНИЙ синтез з RHVoice!
//

import AVFoundation
import Foundation

@available(iOS 16.0, *)
@objc(UkrainianSpeechSynthesizer)
public class UkrainianSpeechSynthesizer: NSObject, AVSpeechSynthesisProviderAudioUnit {
    
    // MARK: - Properties
    
    private var currentRequest: AVSpeechSynthesisProviderRequest?
    private let synthesisQueue = DispatchQueue(label: "com.rhvoice.ukrainian.synthesis", qos: .userInitiated)
    private var audioBuffer: AVAudioPCMBuffer?
    private var framePosition: AVAudioFramePosition = 0
    
    // РЕАЛЬНИЙ RHVoice engine!
    private let rhvoiceEngine: RHVoiceEngine
    
    // MARK: - Initialization
    
    public override init() {
        self.rhvoiceEngine = RHVoiceEngine()
        super.init()
        NSLog("✅ UkrainianSpeechSynthesizer initialized with REAL RHVoice!")
    }
    
    // MARK: - AVSpeechSynthesisProviderAudioUnit
    
    public var speechVoices: [AVSpeechSynthesisProviderVoice] {
        return [
            AVSpeechSynthesisProviderVoice(
                name: "Anatol",
                identifier: "com.rhvoice.ukrainian.anatol",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]
            ),
            AVSpeechSynthesisProviderVoice(
                name: "Natalia",
                identifier: "com.rhvoice.ukrainian.natalia",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]
            ),
            AVSpeechSynthesisProviderVoice(
                name: "Marianna",
                identifier: "com.rhvoice.ukrainian.marianna",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]
            ),
            AVSpeechSynthesisProviderVoice(
                name: "Volodymyr",
                identifier: "com.rhvoice.ukrainian.volodymyr",
                primaryLanguages: ["uk-UA"],
                supportedLanguages: ["uk-UA"]
            )
        ]
    }
    
    public func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
        currentRequest = request
        
        NSLog("🎤 Synthesis request received")
        
        // Асинхронний РЕАЛЬНИЙ синтез
        synthesisQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Параметри
            let rate = Double(request.rate)
            let volume = Double(request.volume)
            let pitch = Double(request.pitch)
            
            // Ім'я голосу
            let voiceIdentifier = request.voice.identifier
            let voiceName = self.extractVoiceName(from: voiceIdentifier)
            
            // Текст
            let text = request.ssmlRepresentation
            
            NSLog("🗣️ Synthesizing: voice=\(voiceName), rate=\(rate), volume=\(volume), pitch=\(pitch)")
            NSLog("📝 Text: \(text.prefix(50))...")
            
            // РЕАЛЬНИЙ синтез через RHVoice!
            if let buffer = self.rhvoiceEngine.synthesize(
                text,
                voice: voiceName,
                rate: rate,
                volume: volume,
                pitch: pitch
            ) {
                self.audioBuffer = buffer
                self.framePosition = 0
                NSLog("✅ Synthesis successful! Buffer: \(buffer.frameLength) frames")
            } else {
                NSLog("❌ Synthesis failed!")
                self.audioBuffer = nil
            }
        }
    }
    
    public func cancelSpeechRequest() {
        NSLog("🛑 Synthesis cancelled")
        currentRequest = nil
        audioBuffer = nil
        framePosition = 0
    }
    
    // MARK: - Render Block
    
    public override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] (
            actionFlags,
            timestamp,
            frameCount,
            outputBusNumber,
            outputAudioBufferList,
            realtimeEventListHead,
            pullInputBlock
        ) in
            guard let self = self else { return kAudioUnitErr_NoConnection }
            
            guard let buffer = self.audioBuffer else {
                return noErr
            }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            
            for bufferIndex in 0..<ablPointer.count {
                guard let targetBuffer = ablPointer[bufferIndex].mData else { continue }
                
                let targetBufferPointer = targetBuffer.assumingMemoryBound(to: Float.self)
                let sourceBufferPointer = buffer.floatChannelData![bufferIndex]
                
                var framesToCopy = min(
                    Int(frameCount),
                    Int(buffer.frameLength) - Int(self.framePosition)
                )
                
                if framesToCopy > 0 {
                    memcpy(
                        targetBufferPointer,
                        sourceBufferPointer.advanced(by: Int(self.framePosition)),
                        framesToCopy * MemoryLayout<Float>.size
                    )
                    self.framePosition += AVAudioFramePosition(framesToCopy)
                }
                
                // Заповнюємо залишок нулями
                if framesToCopy < frameCount {
                    memset(
                        targetBufferPointer.advanced(by: framesToCopy),
                        0,
                        Int(frameCount - UInt32(framesToCopy)) * MemoryLayout<Float>.size
                    )
                }
            }
            
            // Сигналізуємо про завершення
            if self.framePosition >= buffer.frameLength {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
                NSLog("🏁 Rendering complete")
            }
            
            return noErr
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractVoiceName(from identifier: String) -> String {
        let components = identifier.components(separatedBy: ".")
        return components.last ?? "anatol"
    }
}
