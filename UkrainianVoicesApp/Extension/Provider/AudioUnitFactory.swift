import CoreAudioKit
import Foundation

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    private var audioUnit: AUAudioUnit?

    public func beginRequest(with context: NSExtensionContext) {
    }

    @objc
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try UkrainianSpeechSynthesizer(componentDescription: componentDescription, options: [])
        audioUnit = unit
        return unit
    }
}
