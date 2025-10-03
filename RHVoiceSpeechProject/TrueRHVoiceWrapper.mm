#import <Foundation/Foundation.h>
#include "../RHVoice/src/include/RHVoice.h"
#include <vector>

@interface TrueRHVoiceWrapper : NSObject
+ (void)initializeRHVoice;
+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName;
@end

// Callback для получения аудио данных
static std::vector<short> audio_buffer;

static int set_sample_rate_callback(int sample_rate, void* user_data) {
    NSLog(@"🎵 RHVoice sample rate: %d Hz", sample_rate);
    return 1; // success
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    NSLog(@"🎵 RHVoice audio chunk: %u samples", count);
    // Сохраняем аудио данные
    for (unsigned int i = 0; i < count; i++) {
        audio_buffer.push_back(samples[i]);
    }
    return 1; // continue
}

static void done_callback(void* user_data) {
    NSLog(@"✅ RHVoice synthesis completed");
}

@implementation TrueRHVoiceWrapper

static RHVoice_tts_engine engine = NULL;

+ (void)initializeRHVoice {
    NSLog(@"🔧 Инициализация НАСТОЯЩЕГО RHVoice TTS...");
    
    // Настройка callbacks
    RHVoice_callbacks callbacks = {0};
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;
    callbacks.done = done_callback;
    
    // Путь к данным RHVoice
    NSString *dataPath = @"../RHVoice/data";
    
    // Создаем TTS engine
    engine = RHVoice_new_tts_engine([dataPath UTF8String], &callbacks, NULL, RHVoice_preload_voices);
    
    if (engine) {
        NSLog(@"✅ RHVoice TTS engine создан успешно");
        
        // Проверяем доступные голоса
        unsigned int voice_count = RHVoice_get_number_of_voices(engine);
        NSLog(@"📢 Доступно голосов: %u", voice_count);
        
        for (unsigned int i = 0; i < voice_count; i++) {
            const RHVoice_voice_info* voice_info = RHVoice_get_voice_info(engine, i);
            if (voice_info) {
                NSLog(@"🎤 Голос %u: %s (язык: %s)", i, voice_info->name, voice_info->language);
            }
        }
    } else {
        NSLog(@"❌ Не удалось создать RHVoice TTS engine");
    }
}

+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName {
    NSLog(@"🗣️ НАСТОЯЩИЙ RHVoice синтез: '%@' голосом '%@'", text, voiceName);
    
    if (!engine) {
        NSLog(@"❌ RHVoice engine не инициализирован");
        return nil;
    }
    
    // Очищаем буфер
    audio_buffer.clear();
    
    // Устанавливаем голос
    if (![voiceName isEqualToString:@""]) {
        int voice_set = RHVoice_set_voice(engine, [voiceName UTF8String]);
        if (!voice_set) {
            NSLog(@"⚠️ Не удалось установить голос %@, используем по умолчанию", voiceName);
        }
    }
    
    // Выполняем синтез
    const char* text_cstr = [text UTF8String];
    int result = RHVoice_speak(engine, text_cstr, strlen(text_cstr), RHVoice_synth_ssml);
    
    if (result && !audio_buffer.empty()) {
        NSLog(@"✅ Синтез успешен: %zu samples", audio_buffer.size());
        
        // Создаем WAV файл из настоящих аудио данных
        NSMutableData *wavData = [NSMutableData data];
        
        // WAV header
        [wavData appendBytes:"RIFF" length:4];
        uint32_t fileSize = 36 + (uint32_t)(audio_buffer.size() * 2);
        [wavData appendBytes:&fileSize length:4];
        [wavData appendBytes:"WAVE" length:4];
        [wavData appendBytes:"fmt " length:4];
        uint32_t fmtSize = 16;
        [wavData appendBytes:&fmtSize length:4];
        uint16_t audioFormat = 1; // PCM
        [wavData appendBytes:&audioFormat length:2];
        uint16_t numChannels = 1; // mono
        [wavData appendBytes:&numChannels length:2];
        uint32_t sampleRate = 24000; // RHVoice default
        [wavData appendBytes:&sampleRate length:4];
        uint32_t byteRate = sampleRate * 2;
        [wavData appendBytes:&byteRate length:4];
        uint16_t blockAlign = 2;
        [wavData appendBytes:&blockAlign length:2];
        uint16_t bitsPerSample = 16;
        [wavData appendBytes:&bitsPerSample length:2];
        [wavData appendBytes:"data" length:4];
        uint32_t dataSize = (uint32_t)(audio_buffer.size() * 2);
        [wavData appendBytes:&dataSize length:4];
        
        // Добавляем настоящие аудио данные от RHVoice
        [wavData appendBytes:audio_buffer.data() length:audio_buffer.size() * sizeof(short)];
        
        NSLog(@"📄 WAV файл создан: %lu байт", (unsigned long)[wavData length]);
        return wavData;
        
    } else {
        NSLog(@"❌ RHVoice синтез не удался");
        return nil;
    }
}

@end
