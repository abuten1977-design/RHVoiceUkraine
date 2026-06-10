import CoreAudioKit
import Foundation
import RHVoiceBridge

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    private var audioUnit: AUAudioUnit?

    public func beginRequest(with context: NSExtensionContext) {
        "EXT_DIAG beginRequest".withCString { RHVoiceDebugLogString($0) }
    }

    @objc
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        "EXT_DIAG createAudioUnit type=\(componentDescription.componentType) subtype=\(componentDescription.componentSubType)".withCString {
            RHVoiceDebugLogString($0)
        }
        let unit = try UkrainianSpeechSynthesizer(componentDescription: componentDescription, options: [])
        audioUnit = unit
        return unit
    }
}
