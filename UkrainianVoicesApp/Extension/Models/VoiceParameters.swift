//
//  VoiceParameters.swift
//  PolishVariant
//
//  Объединенные параметры синтеза
//

import Foundation

/// Структура, объединяющая параметры синтеза из польского проекта и новые (speed/pauses).
public struct VoiceParameters: Codable, Equatable {
    
    // MARK: - Polish Project Parameters (Standard RHVoice)
    
    /// Основная скорость речи (Rate).
    /// Диапазон: 0.1 (очень медленно) ... 4.0 (очень быстро).
    /// Стандарт: 1.0
    public var rate: Float = 1.0
    
    /// Высота тона (Pitch).
    /// Диапазон: 0.5 (низкий) ... 2.0 (высокий).
    /// Стандарт: 1.0
    public var pitch: Float = 1.0
    
    /// Громкость (Volume).
    /// Диапазон: 0.0 (тишина) ... 1.0 (максимум).
    /// Стандарт: 1.0
    public var volume: Float = 1.0
    
    // MARK: - New Parameters (Ukraine Specific)
    
    /// Множитель скорости для VoiceOver (Speed).
    /// Позволяет дополнительно ускорять/замедлять синтез.
    /// Диапазон: 0.5 ... 3.0
    /// Стандарт: 1.0
    public var speed: Float = 1.0
    
    /// Множитель длительности пауз (Pause Duration).
    /// Влияет на паузы между предложениями.
    /// Диапазон: 0.2 (короткие) ... 3.0 (длинные)
    /// Стандарт: 1.0
    public var pauseDuration: Float = 1.0
    
    public init() {}
    
    // MARK: - Validation
    
    /// Возвращает валидированную версию параметров.
    public func validated() -> VoiceParameters {
        var copy = self
        copy.rate = max(0.1, min(4.0, rate))
        copy.pitch = max(0.5, min(2.0, pitch))
        copy.volume = max(0.0, min(1.0, volume))
        copy.speed = max(0.5, min(3.0, speed))
        copy.pauseDuration = max(0.2, min(3.0, pauseDuration))
        return copy
    }
}
