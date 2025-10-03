#include <iostream>
#include <fstream>
#include <vector>
#include <dlfcn.h>
#include "../RHVoice/src/include/RHVoice.h"

// Глобальные переменные для аудио данных
std::vector<short> audio_buffer;
int current_sample_rate = 24000;

// Callback функции
int set_sample_rate_callback(int sample_rate, void* user_data) {
    std::cout << "🎵 RHVoice sample rate: " << sample_rate << " Hz" << std::endl;
    current_sample_rate = sample_rate;
    return 1;
}

int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    std::cout << "🎵 RHVoice audio chunk: " << count << " samples" << std::endl;
    for (unsigned int i = 0; i < count; i++) {
        audio_buffer.push_back(samples[i]);
    }
    return 1;
}

void done_callback(void* user_data) {
    std::cout << "✅ RHVoice synthesis completed, total samples: " << audio_buffer.size() << std::endl;
}

void save_wav(const std::string& filename, const std::vector<short>& data, int sample_rate) {
    std::ofstream file(filename, std::ios::binary);
    
    // WAV header
    file.write("RIFF", 4);
    uint32_t file_size = 36 + data.size() * 2;
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
    uint32_t data_size = data.size() * 2;
    file.write(reinterpret_cast<const char*>(&data_size), 4);
    
    // Audio data
    file.write(reinterpret_cast<const char*>(data.data()), data.size() * sizeof(short));
    
    std::cout << "📄 WAV файл сохранен: " << filename << " (" << data.size() * 2 << " байт)" << std::endl;
}

int main() {
    std::cout << "🚀 ПРАВИЛЬНЫЙ тест RHVoice на macOS" << std::endl;
    
    // Настройка callbacks
    RHVoice_callbacks callbacks = {0};
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;
    callbacks.done = done_callback;
    
    // Путь к данным RHVoice
    const char* data_path = "/Users/admin/RHVoiceUkraine/RHVoice/data";
    const char* resource_paths[] = {data_path, NULL};
    
    std::cout << "📁 Используем путь к данным: " << data_path << std::endl;
    
    // Параметры инициализации
    RHVoice_init_params init_params = {0};
    init_params.resource_paths = resource_paths;
    init_params.callbacks = callbacks;
    init_params.options = RHVoice_preload_voices;
    
    // Создаем TTS engine
    std::cout << "🔧 Создаем НАСТОЯЩИЙ RHVoice TTS engine..." << std::endl;
    RHVoice_tts_engine engine = RHVoice_new_tts_engine(&init_params);
    
    if (engine) {
        std::cout << "✅ НАСТОЯЩИЙ RHVoice TTS engine создан успешно!" << std::endl;
        
        // Проверяем доступные голоса
        unsigned int voice_count = RHVoice_get_number_of_voices(engine);
        std::cout << "📢 Доступно голосов: " << voice_count << std::endl;
        
        const RHVoice_voice_info* voices = RHVoice_get_voices(engine);
        for (unsigned int i = 0; i < voice_count; i++) {
            std::cout << "🎤 Голос " << i << ": " << voices[i].name << " (язык: " << voices[i].language << ")" << std::endl;
        }
        
        // Тест синтеза украинских голосов
        std::vector<std::string> voice_names = {"natalia", "marianna", "volodymyr", "anatol"};
        std::vector<std::string> texts = {
            "Привіт! Мене звати Наталія. Це справжній RHVoice синтез українською мовою!",
            "Вітаю! Це голос Маріанни від RHVoice. Україна - моя Батьківщина!",
            "Доброго дня! Володимир говорить через RHVoice. Україна понад усе!",
            "Здоровенькі були! Анатолій використовує RHVoice для української мови!"
        };
        
        for (size_t i = 0; i < voice_names.size(); i++) {
            std::cout << "\n🗣️ Тестируем голос: " << voice_names[i] << std::endl;
            audio_buffer.clear();
            
            // Параметры синтеза
            RHVoice_synth_params synth_params = {0};
            synth_params.voice_profile = voice_names[i].c_str();
            
            // Создаем сообщение
            const char* text = texts[i].c_str();
            RHVoice_message message = RHVoice_new_message(
                engine, 
                text, 
                strlen(text), 
                RHVoice_message_text, 
                &synth_params, 
                NULL
            );
            
            if (message) {
                std::cout << "📝 Сообщение создано, выполняем НАСТОЯЩИЙ синтез..." << std::endl;
                
                int result = RHVoice_speak(message);
                RHVoice_delete_message(message);
                
                if (result && !audio_buffer.empty()) {
                    std::cout << "✅ НАСТОЯЩИЙ синтез успешен: " << audio_buffer.size() << " samples" << std::endl;
                    
                    // Сохраняем WAV файл
                    std::string filename = "real_" + voice_names[i] + "_voice.wav";
                    save_wav(filename, audio_buffer, current_sample_rate);
                    std::cout << "🎉 НАСТОЯЩИЙ украинский голос " << voice_names[i] << " создан!" << std::endl;
                } else {
                    std::cout << "❌ Синтез не удался для " << voice_names[i] << std::endl;
                }
            } else {
                std::cout << "❌ Не удалось создать сообщение для " << voice_names[i] << std::endl;
            }
        }
        
        RHVoice_delete_tts_engine(engine);
        std::cout << "\n🎉 НАСТОЯЩИЙ RHVoice тест завершен!" << std::endl;
    } else {
        std::cout << "❌ Не удалось создать НАСТОЯЩИЙ RHVoice TTS engine" << std::endl;
        return 1;
    }
    
    return 0;
}
