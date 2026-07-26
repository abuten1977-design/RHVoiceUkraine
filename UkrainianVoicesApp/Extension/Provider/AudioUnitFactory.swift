import CoreAudioKit
import Foundation
import RHVoiceBridge

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    private var audioUnit: AUAudioUnit?

    public func beginRequest(with context: NSExtensionContext) {
        // iOS speech-provider extension cannot write our shared diagnostic
        // file reliably. NSLog remains observable through idevicesyslog and
        // avoids a sandbox-denial loop during voice enumeration.
        NSLog("VOICE_CATALOG_DIAG extension=beginRequest")
    }

    @objc
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        NSLog(
            "VOICE_CATALOG_DIAG extension=createAudioUnit type=%u subtype=%u",
            componentDescription.componentType,
            componentDescription.componentSubType
        )
        let unit = try UkrainianSpeechSynthesizer(componentDescription: componentDescription, options: [])
        audioUnit = unit
        return unit
    }
}
