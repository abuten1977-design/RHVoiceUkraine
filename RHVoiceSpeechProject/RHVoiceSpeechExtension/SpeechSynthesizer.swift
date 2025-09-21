
import AVFoundation
import RHVoiceFramework // Импортируем наш фреймворк

class SpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {

    override init() {
        super.init()
        // Инициализация RHVoice при создании синтезатора
        RHVoiceWrapper.initializeRHVoice()
    }

    override func synthesizeSpeechRequest(_ request: AVSpeechSynthesisProviderSpeechRequest, completion: @escaping (AVSpeechSynthesisProviderSpeechFrame?) -> Void) {
        guard let text = request.ssmlRepresentation else {
            completion(nil)
            return
        }

        // Call RHVoiceWrapper to synthesize text
        let audioData = RHVoiceWrapper.synthesizeText(text, withVoice: "uk-natalia")

        if let audioData = audioData, audioData.count > 0 {
            // Create an AVSpeechSynthesisProviderSpeechFrame with the audio data
            // Assuming audioData is a single block of uncompressed PCM audio
            let audioFrame = AVSpeechSynthesisProviderSpeechFrame(audioBytes: audioData, packetCount: 1, packetDescriptions: nil)
            completion(audioFrame)
        }
        // Signal the end of speech by sending a nil frame
        completion(nil)
    }

    override func voiceIsAvailable(withIdentifier identifier: String) -> Bool {
        // Здесь будет логика проверки доступности голоса RHVoice
        // Пока всегда возвращаем true для украинских голосов
        return identifier.hasPrefix("uk-")
    }

    override func supportedVoices() -> [AVSpeechSynthesisProviderVoice] {
        // Здесь будет список поддерживаемых голосов RHVoice
        // Пока возвращаем заглушку для украинского голоса
        let nataliaVoice = AVSpeechSynthesisProviderVoice(identifier: "uk-natalia", name: "Natalia (RHVoice)", primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"])
        return [nataliaVoice]
    }
}
