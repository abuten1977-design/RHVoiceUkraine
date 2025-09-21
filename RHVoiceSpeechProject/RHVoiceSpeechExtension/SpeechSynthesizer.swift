
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

        // Здесь будет вызов RHVoiceWrapper для синтеза текста
        // Пока возвращаем пустой фрейм, чтобы не блокировать
        let audioData = RHVoiceWrapper.synthesizeText(text, withVoice: "uk-natalia") // Пример вызова

        // В реальной реализации нужно будет разбить audioData на фреймы
        // и отправлять их через completion
        // For now, just complete with nil to avoid crashing
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
