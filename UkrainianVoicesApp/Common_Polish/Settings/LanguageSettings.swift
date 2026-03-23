//
//  LanguageSettings.swift (MODIFIED FOR TURBO-SPEED)
//

import Foundation
import RHVoice

public class LanguageSettings: Codable {
    public var rate: Double = RHVoiceParameters.rate().defaultValue
    public var volume: Double = RHVoiceParameters.volume().defaultValue
    public var speedMultiplier: Double = 1.0
    public var sentencePause: Int = 0
    
    // Новые параметры (Твои 'ускорители')
    public var multiplier: Double = 1.0 // От 1.0 до 3.0
    public var wordPause: Int = 0       // В миллисекундах
    public var punctuationPause: Int = 0 // В миллисекундах
}

extension LanguageSettings {
    public static var rateRange: ClosedRange<Double> {
        return RHVoiceParameters.rate().range
    }
    
    public static var volumeRange: ClosedRange<Double> {
        return RHVoiceParameters.volume().range
    }

    public static var speedMultiplierRange: ClosedRange<Double> {
        return 1.0...5.0
    }

    public static var sentencePauseRange: ClosedRange<Double> {
        return 0...2000
    }
    
    // Диапазон для твоего множителя
    public static var multiplierRange: ClosedRange<Double> {
        return 1.0...3.0
    }
}

fileprivate extension RHVoiceParameters {
    var range: ClosedRange<Double> {
        return min...max
    }
}
