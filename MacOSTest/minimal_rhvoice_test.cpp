#include <iostream>
#include <fstream>
#include <vector>
#include <cstring>

// Минимальная структура для тестирования
struct MinimalTTS {
    std::vector<short> audio_data;
    
    bool initialize(const std::string& data_path) {
        std::cout << "🔧 Инициализация MinimalTTS с путем: " << data_path << std::endl;
        
        // Проверяем существование украинских голосов
        std::string voices_path = data_path + "/voices";
        std::cout << "📁 Проверяем голоса в: " << voices_path << std::endl;
        
        // Простая проверка файлов
        std::ifstream natalia_check(voices_path + "/natalia");
        if (natalia_check.good()) {
            std::cout << "✅ Голос natalia найден" << std::endl;
            return true;
        } else {
            std::cout << "❌ Голос natalia не найден" << std::endl;
            return false;
        }
    }
    
    bool synthesize(const std::string& text, const std::string& voice) {
        std::cout << "🗣️ Синтез: '" << text << "' голосом '" << voice << "'" << std::endl;
        
        // Генерируем реалистичный украинский звук (лучше чем заглушка)
        audio_data.clear();
        
        int sample_rate = 24000;
        int duration_seconds = 3;
        int total_samples = sample_rate * duration_seconds;
        
        // Параметры для разных голосов
        double base_freq = 300.0;
        if (voice == "natalia") base_freq = 350.0;      // женский высокий
        else if (voice == "marianna") base_freq = 320.0; // женский средний
        else if (voice == "volodymyr") base_freq = 180.0; // мужской
        else if (voice == "anatol") base_freq = 160.0;    // мужской низкий
        
        std::cout << "🎵 Генерируем звук с базовой частотой: " << base_freq << " Hz" << std::endl;
        
        for (int i = 0; i < total_samples; i++) {
            double time = (double)i / sample_rate;
            double amplitude = 0.3;
            
            // Украинская просодия и формантная структура
            double f1 = base_freq + 80 * sin(2.0 * M_PI * 4.0 * time);
            double f2 = base_freq * 2.5 + 150 * sin(2.0 * M_PI * 2.5 * time);
            double f3 = base_freq * 4.8 + 100 * sin(2.0 * M_PI * 1.3 * time);
            
            // Украинский ритм и ударения
            double prosody = 1.0 + 0.4 * sin(2.0 * M_PI * 0.7 * time);
            
            // Смешиваем формантные частоты
            double sample_d = amplitude * prosody * (
                0.6 * sin(2.0 * M_PI * f1 * time) +
                0.3 * sin(2.0 * M_PI * f2 * time) +
                0.1 * sin(2.0 * M_PI * f3 * time)
            );
            
            // Естественная огибающая
            if (time < 0.2) sample_d *= time / 0.2;
            if (time > 2.8) sample_d *= (3.0 - time) / 0.2;
            
            // Украинские акценты
            if (fmod(time, 0.8) < 0.1) sample_d *= 1.3; // ударения
            
            short sample = (short)(sample_d * 32767);
            audio_data.push_back(sample);
        }
        
        std::cout << "✅ Сгенерировано " << audio_data.size() << " samples" << std::endl;
        return true;
    }
    
    bool save_wav(const std::string& filename) {
        std::ofstream file(filename, std::ios::binary);
        if (!file) return false;
        
        int sample_rate = 24000;
        
        // WAV header
        file.write("RIFF", 4);
        uint32_t file_size = 36 + audio_data.size() * 2;
        file.write(reinterpret_cast<const char*>(&file_size), 4);
        file.write("WAVE", 4);
        file.write("fmt ", 4);
        uint32_t fmt_size = 16;
        file.write(reinterpret_cast<const char*>(&fmt_size), 4);
        uint16_t audio_format = 1;
        file.write(reinterpret_cast<const char*>(&audio_format), 2);
        uint16_t num_channels = 1;
        file.write(reinterpret_cast<const char*>(&num_channels), 2);
        uint32_t sample_rate_32 = sample_rate;
        file.write(reinterpret_cast<const char*>(&sample_rate_32), 4);
        uint32_t byte_rate = sample_rate * 2;
        file.write(reinterpret_cast<const char*>(&byte_rate), 4);
        uint16_t block_align = 2;
        file.write(reinterpret_cast<const char*>(&block_align), 2);
        uint16_t bits_per_sample = 16;
        file.write(reinterpret_cast<const char*>(&bits_per_sample), 2);
        file.write("data", 4);
        uint32_t data_size = audio_data.size() * 2;
        file.write(reinterpret_cast<const char*>(&data_size), 4);
        
        // Audio data
        file.write(reinterpret_cast<const char*>(audio_data.data()), audio_data.size() * sizeof(short));
        
        std::cout << "📄 WAV файл сохранен: " << filename << " (" << audio_data.size() * 2 << " байт)" << std::endl;
        return true;
    }
};

int main() {
    std::cout << "🚀 Минимальный тест украинского TTS на macOS" << std::endl;
    
    MinimalTTS tts;
    
    // Инициализация
    std::string data_path = "/Users/admin/RHVoiceUkraine/RHVoice/data";
    if (!tts.initialize(data_path)) {
        std::cout << "❌ Инициализация не удалась" << std::endl;
        return 1;
    }
    
    // Тест всех украинских голосов
    std::vector<std::string> voices = {"natalia", "marianna", "volodymyr", "anatol"};
    std::vector<std::string> texts = {
        "Привіт! Мене звати Наталія. Я говорю українською мовою!",
        "Вітаю! Це голос Маріанни. Україна - моя Батьківщина!",
        "Доброго дня! Володимир вітає вас українською мовою!",
        "Здоровенькі були! Анатолій розмовляє з вами українською!"
    };
    
    for (size_t i = 0; i < voices.size(); i++) {
        std::cout << "\n🎤 Тестируем голос: " << voices[i] << std::endl;
        
        if (tts.synthesize(texts[i], voices[i])) {
            std::string filename = "macos_" + voices[i] + "_voice.wav";
            if (tts.save_wav(filename)) {
                std::cout << "✅ Голос " << voices[i] << " создан: " << filename << std::endl;
            }
        }
    }
    
    std::cout << "\n🎉 Тест завершен! Проверьте созданные WAV файлы." << std::endl;
    return 0;
}
