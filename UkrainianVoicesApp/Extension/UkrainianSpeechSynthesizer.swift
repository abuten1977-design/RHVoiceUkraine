import AVFoundation
import AudioToolbox

/// Ukrainian Speech Synthesis Provider Extension
/// Registers Ukrainian voices (Anatol, Marianna) with the system
/// VoiceOver can use these voices for speech synthesis
@available(iOS 13.0, macOS 10.15, *)
public class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    
    // MARK: - Properties
    private var synthesisQueue = DispatchQueue(label: "com.ukraine.synthesis", qos: .userInitiated)
    private var outputAudioBuffer: [Float] = []
    private var isProcessing = false
    
    // RHVoice parameters
    private var currentRate: Float = 1.0
    private var currentPitch: Float = 1.0
    private var currentVolume: Float = 1.0
    private var sentencePauseDuration: Int = 0 // ms
    
    // MARK: - Initialization
    public override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        initializeAudioUnit()
    }
    
    /// Initialize Audio Unit configuration
    private func initializeAudioUnit() {
        // Set default audio format: 44100Hz, mono, 32-bit float
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 44100,
                                       channels: 1,
                                       interleaved: false)
        
        // Configure input and output bus
        let inputBus = AUAudioUnitBus(format: audioFormat)
        let outputBus = AUAudioUnitBus(format: audioFormat)
        
        // Initialize busses
        do {
            let inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
            let outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
            
            try self.setInputBusses(inputBusArray)
            try self.setOutputBusses(outputBusArray)
        } catch {
            print("❌ Failed to initialize audio buses: \(error)")
        }
    }
    
    // MARK: - Speech Synthesis Protocol Implementation
    
    /// Synthesize speech request from AVSpeechSynthesisProviderRequest
    public override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderRequest) {
        synthesisQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isProcessing = true
            defer { self.isProcessing = false }
            
            // Extract speech parameters
            let ssmlText = request.ssmlRepresentation
            let voice = request.voice
            let rate = Float(request.rate) // 0.0...1.0 (0.5 = slower, 1.0 = normal, 2.0 = faster)
            let pitch = Float(request.pitchMultiplier) // 0.5...2.0
            let volume = Float(request.volume) // 0.0...1.0
            
            // Store parameters for synthesis
            self.currentRate = rate
            self.currentPitch = pitch
            self.currentVolume = volume
            
            // Synthesize text to audio samples
            let audioSamples = self.synthesizeText(ssmlText, voice: voice.identifier,
                                                   rate: rate, pitch: pitch, volume: volume)
            
            // Send audio to AVSpeechSynthesisProviderAudioUnit
            self.sendAudioSamples(audioSamples)
            
            // Signal synthesis completion
            self.signalSynthesisCompletion()
        }
    }
    
    /// Synthesize SSML text to audio samples using RHVoice
    private func synthesizeText(_ ssmlText: String, voice: String, 
                               rate: Float, pitch: Float, volume: Float) -> [Float] {
        var audioSamples: [Float] = []
        
        // Parse SSML or plain text
        let plainText = stripSSMLTags(ssmlText)
        
        // TODO: Call RHVoice C++ bridge to synthesize
        // This requires:
        // 1. Load voice if not loaded: rhvoice_load_voice(voice)
        // 2. Set rate parameter: rhvoice_set_parameter("rate", rate)
        // 3. Set pitch parameter: rhvoice_set_parameter("pitch", pitch)
        // 4. Synthesize text: rhvoice_synthesize(text, &outputBuffer)
        // 5. Apply volume: multiply samples by volume factor
        
        // For now, placeholder that returns silent audio
        // In final version, this calls RHVoiceBridge
        let sampleCount = Int(44100 * Double(plainText.count) / 1000) // Rough estimate
        audioSamples = [Float](repeating: 0.0, count: sampleCount)
        
        // Apply volume scaling
        audioSamples = audioSamples.map { $0 * volume }
        
        return audioSamples
    }
    
    /// Send audio samples to the system
    private func sendAudioSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        
        // Create AVAudioPCMBuffer from samples
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 44100,
                                   channels: 1,
                                   interleaved: false)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                           frameCapacity: AVAudioFrameCount(samples.count)) else {
            print("❌ Failed to create audio buffer")
            return
        }
        
        // Copy samples to buffer
        let floatChannelData = buffer.floatChannelData!
        for i in 0..<samples.count {
            floatChannelData[0][i] = samples[i]
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        // Send to output
        outputAudioBuffer = samples
    }
    
    /// Signal to system that synthesis is complete
    private func signalSynthesisCompletion() {
        // TODO: Call appropriate AVSpeechSynthesisProviderAudioUnit method
        // This signals to VoiceOver/system that speech is ready
    }
    
    // MARK: - Supported Voices
    
    /// List of Ukrainian voices available in this extension
    public override var supportedVoices: [AVSpeechSynthesisProviderVoice] {
        return [
            // Male voice
            AVSpeechSynthesisProviderVoice(
                name: "Anatol",
                identifier: "com.ukraine.voice.anatol",
                primaryLanguage: "uk-UA",
                gender: .male,
                quality: .enhanced,
                version: "1.0"
            ),
            // Female voice  
            AVSpeechSynthesisProviderVoice(
                name: "Marianna",
                identifier: "com.ukraine.voice.marianna",
                primaryLanguage: "uk-UA",
                gender: .female,
                quality: .enhanced,
                version: "1.0"
            )
        ]
    }
    
    // MARK: - Helper Methods
    
    /// Strip SSML tags from text (convert SSML to plain text)
    private func stripSSMLTags(_ ssmlText: String) -> String {
        // Remove <speak>, <voice>, <prosody> tags, etc.
        var result = ssmlText
        
        // Remove common SSML tags
        result = result.replacingOccurrences(of: "<speak>", with: "")
        result = result.replacingOccurrences(of: "</speak>", with: "")
        result = result.replacingOccurrences(of: "<voice.*?>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "</voice>", with: "")
        result = result.replacingOccurrences(of: "<prosody.*?>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "</prosody>", with: "")
        result = result.replacingOccurrences(of: "<emphasis.*?>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "</emphasis>", with: "")
        result = result.replacingOccurrences(of: "<break.*?>", with: "", options: .regularExpression)
        
        // Decode HTML entities
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        
        return result.trimmingCharacters(in: .whitespaces)
    }
}
