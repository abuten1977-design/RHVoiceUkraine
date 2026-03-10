//
//  UkrainianSpeechSynthesizer.swift
//  Ukrainian Voices Extension
//
//  РЕАЛЬНИЙ синтез з RHVoice!
//

import AVFoundation
import AVFAudio

@available(iOS 16.0, *)
@objc(UkrainianSpeechSynthesizer)
public class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    
    // MARK: - Properties
    
    private var currentRequest: AVSpeechSynthesisProviderRequest?
    private let synthesisQueue = DispatchQueue(label: "com.rhvoice.ukrainian.synthesis", qos: .userInitiated)
    private var audioBuffer: AVAudioPCMBuffer?
    private var framePosition: AVAudioFramePosition = 0
    
    // РЕАЛЬНИЙ RHVoice engine!
    private let rhvoiceEngine: RHVoiceEngine
    
    // Голоси
    private var _speechVoices: [AVSpeechSynthesisProviderVoice] = []
    
    // MARK: - Initialization
    
    public override init(componentDescription: AudioComponentDescription,
                        options: AudioComponentInstantiationOptions = []) throws {
        self.rhvoiceEngine = RHVoiceEngine()
        try super.init(componentDescription: componentDescription, options: options)
        
        // Ініціалізуємо голоси
        _speechVoices = [
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
        
        NSLog("✅ UkrainianSpeechSynthesizer initialized with REAL RHVoice!")
    }
    
    // MARK: - AVSpeechSynthesisProviderAudioUnit
    
    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get { return _speechVoices }
        set { _speechVoices = newValue }
    }
    
    public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
        currentRequest = request
        
        NSLog("🎤 Synthesis request received")
        
        // Асинхронний РЕАЛЬНИЙ синтез
        synthesisQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Параметри (використовуємо дефолтні значення, бо API не надає їх напряму)
            let rate = 1.0
            let volume = 1.0
            let pitch = 1.0
            
            // Ім'я голосу
            let voiceIdentifier = request.voice.identifier
            let voiceName = self.extractVoiceName(from: voiceIdentifier)
            
            // Текст
            let text = request.ssmlRepresentation
            
            NSLog("🗣️ Synthesizing: voice=\(voiceName)")
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
    
    public override func cancelSpeechRequest() {
        NSLog("🛑 Synthesis cancelled")
        currentRequest = nil
        audioBuffer = nil
        framePosition = 0
    }
    
    // MARK: - AUAudioUnit Render
    
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
                // Тиша, якщо немає буфера
                let ablPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
                for bufferIndex in 0..<ablPointer.count {
                    if let targetBuffer = ablPointer[bufferIndex].mData {
                        memset(targetBuffer, 0, Int(ablPointer[bufferIndex].mDataByteSize))
                    }
                }
                return noErr
            }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
            
            for bufferIndex in 0..<ablPointer.count {
                guard let targetBuffer = ablPointer[bufferIndex].mData else { continue }
                
                let targetBufferPointer = targetBuffer.assumingMemoryBound(to: Float.self)
                let sourceBufferPointer = buffer.floatChannelData![bufferIndex]
                
                let framesToCopy = min(
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
