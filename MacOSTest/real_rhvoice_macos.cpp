#include <iostream>
#include <memory>
#include <fstream>
#include <vector>

// Попробуем включить RHVoice core напрямую
#include "../RHVoice/src/core/engine.hpp"
#include "../RHVoice/src/core/document.hpp"

class MacOSRHVoiceTest {
private:
    std::unique_ptr<RHVoice::engine> tts_engine;
    std::vector<short> audio_buffer;
    
public:
    bool initialize(const std::string& data_path) {
        std::cout << "🔧 Инициализация настоящего RHVoice engine..." << std::endl;
        std::cout << "📁 Путь к данным: " << data_path << std::endl;
        
        try {
            // Создаем настоящий RHVoice engine
            tts_engine = std::make_unique<RHVoice::engine>(data_path);
            std::cout << "✅ RHVoice engine создан успешно!" << std::endl;
            
            // Проверяем доступные голоса
            auto voices = tts_engine->get_voices();
            std::cout << "📢 Найдено голосов: " << voices.size() << std::endl;
            
            for (const auto& voice : voices) {
                std::cout << "🎤 Голос: " << voice->get_name() << " (язык: " << voice->get_language().get_alpha2_code() << ")" << std::endl;
            }
            
            return true;
        } catch (const std::exception& e) {
            std::cout << "❌ Ошибка создания engine: " << e.what() << std::endl;
            return false;
        }
    }
    
    bool synthesize(const std::string& text, const std::string& voice_name) {
        if (!tts_engine) {
            std::cout << "❌ Engine не инициализирован" << std::endl;
            return false;
        }
        
        std::cout << "🗣️ НАСТОЯЩИЙ синтез: '" << text << "' голосом '" << voice_name << "'" << std::endl;
        
        try {
            // Ищем голос
            auto voices = tts_engine->get_voices();
            RHVoice::voice_ptr selected_voice = nullptr;
            
            for (const auto& voice : voices) {
                if (voice->get_name() == voice_name) {
                    selected_voice = voice;
                    break;
                }
            }
            
            if (!selected_voice) {
                std::cout << "❌ Голос '" << voice_name << "' не найден" << std::endl;
                return false;
            }
            
            std::cout << "✅ Голос найден: " << selected_voice->get_name() << std::endl;
            
            // Создаем документ для синтеза
            RHVoice::document doc(text, RHVoice::content_text, selected_voice, RHVoice::quality_max);
            
            // Выполняем синтез
            audio_buffer.clear();
            
            // Здесь нужно реализовать callback для получения аудио данных
            // Это более сложная часть, требующая изучения RHVoice API
            
            std::cout << "⚠️ Синтез требует дополнительной реализации callback'ов" << std::endl;
            return false;
            
        } catch (const std::exception& e) {
            std::cout << "❌ Ошибка синтеза: " << e.what() << std::endl;
            return false;
        }
    }
};

int main() {
    std::cout << "🚀 Тест настоящего RHVoice на macOS" << std::endl;
    
    MacOSRHVoiceTest test;
    
    std::string data_path = "/Users/admin/RHVoiceUkraine/RHVoice/data";
    if (test.initialize(data_path)) {
        std::cout << "✅ Инициализация успешна!" << std::endl;
        
        // Попробуем синтез
        test.synthesize("Привіт! Це тест RHVoice.", "natalia");
    } else {
        std::cout << "❌ Инициализация не удалась" << std::endl;
    }
    
    return 0;
}
