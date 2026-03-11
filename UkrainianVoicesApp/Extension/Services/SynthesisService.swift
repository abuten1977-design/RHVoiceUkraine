//
//  SynthesisService.swift
//  PolishVariant
//
//  Сервис синтеза, интегрирующий параметры
//

import Foundation
import AVFoundation

public class SynthesisService {
    public static let shared = SynthesisService()
    
    private let engine = RHVoiceEngine()
    private let voiceManager = VoiceManager.shared
    
    // MARK: - Synthesis
    
    /// Основной метод синтеза, который использует параметры пользователя.
    /// - Parameters:
    ///   - text: Текст для синтеза
    ///   - voice: Имя голоса
    /// - Returns: Аудио буфер
    public func synthesize(text: String, voice: String) -> AVAudioPCMBuffer? {
        let params = voiceManager.parameters
        
        // Логика объединения rate от VoiceOver и нашего speed
        // В реальном AVSpeechSynthesisProviderVoice мы получаем rate из request,
        // но здесь мы берем базовые настройки пользователя.
        
        let finalRate = params.rate * params.speed
        
        return engine.synthesize(
            text,
            voice: voice,
            rate: Double(finalRate),
            volume: Double(params.volume),
            pitch: Double(params.pitch),
            pauseDuration: Double(params.pauseDuration) // Новый параметр!
        )
    }
}
