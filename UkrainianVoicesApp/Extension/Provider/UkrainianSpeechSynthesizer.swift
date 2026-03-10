//
//  UkrainianSpeechSynthesizer.swift
//  Ukrainian Voices Extension
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
    
    // RHVoice engine wrapper
    private let rhvoiceEngine: RHVoiceEngineWrapper
    
    // MARK: - Initialization
    
    public override init() {
        self.rhvoiceEngine = RHVoiceEngineWrapper()
        super.init()
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
        
        // Асинхронный синтез
        synthesisQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Извлекаем параметры
            let rate = request.rate
            let volume = request.volume
            let pitch = request.pitch
            
            // Извлекаем имя голоса
            let voiceIdentifier = request.voice.identifier
            let voiceName = self.extractVoiceName(from: voiceIdentifier)
            
            // Получаем текст (SSML или plain text)
            let text = request.ssmlRepresentation
            
            // Синтезируем через RHVoice
            if let buffer = self.rhvoiceEngine.synthesize(
                text: text,
                voice: voiceName,
                rate: Double(rate),
                volume: Double(volume),
                pitch: Double(pitch)
            ) {
                self.audioBuffer = buffer
                self.framePosition = 0
            } else {
                // Ошибка синтеза
                self.audioBuffer = nil
            }
        }
    }
    
    public func cancelSpeechRequest() {
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
                
                // Заполняем остаток нулями если нужно
                if framesToCopy < frameCount {
                    memset(
                        targetBufferPointer.advanced(by: framesToCopy),
                        0,
                        Int(frameCount - UInt32(framesToCopy)) * MemoryLayout<Float>.size
                    )
                }
            }
            
            // Сигнализируем о завершении
            if self.framePosition >= buffer.frameLength {
                actionFlags.pointee = .offlineUnitRenderAction_Complete
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

// MARK: - RHVoice Engine Wrapper

class RHVoiceEngineWrapper {
    
    func synthesize(
        text: String,
        voice: String,
        rate: Double,
        volume: Double,
        pitch: Double
    ) -> AVAudioPCMBuffer? {
        
        // TODO: Подключить реальный RHVoice C API
        // Пока возвращаем тестовый буфер
        
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 24000,
            channels: 1
        )!
        
        let frameCount = AVAudioFrameCount(24000) // 1 секунда
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // Генерируем тестовый тон (440 Hz)
        if let channelData = buffer.floatChannelData {
            let frequency: Float = 440.0
            let sampleRate: Float = 24000.0
            
            for frame in 0..<Int(frameCount) {
                let value = sin(2.0 * .pi * frequency * Float(frame) / sampleRate)
                channelData[0][frame] = value * Float(volume)
            }
        }
        
        return buffer
    }
}
