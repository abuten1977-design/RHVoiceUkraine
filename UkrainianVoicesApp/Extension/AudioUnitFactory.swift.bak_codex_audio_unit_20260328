import AVFoundation
import AudioToolbox

/// Audio Unit Factory for Speech Synthesis
/// Creates and configures AVSpeechSynthesisProviderAudioUnit instances
@available(iOS 13.0, macOS 10.15, *)
public class AudioUnitFactory: NSObject, AVSpeechSynthesisProviderAudioUnitFactory {
    
    /// Create Audio Unit for speech synthesis
    /// - Parameter componentDescription: Audio component configuration
    /// - Returns: Configured UkrainianSpeechSynthesizer instance
    /// - Throws: If Audio Unit creation fails
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AVSpeechSynthesisProviderAudioUnit {
        
        // Create UkrainianSpeechSynthesizer Audio Unit
        let audioUnit = try UkrainianSpeechSynthesizer(componentDescription: componentDescription, options: [])
        
        return audioUnit
    }
}
