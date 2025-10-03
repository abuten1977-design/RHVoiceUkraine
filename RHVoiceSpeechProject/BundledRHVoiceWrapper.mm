#import <Foundation/Foundation.h>
#include "../RHVoice/src/include/RHVoice.h"
#include <vector>

@interface BundledRHVoiceWrapper : NSObject
+ (void)initializeRHVoice;
+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName;
@end

// Глобальные переменные для аудио данных
static std::vector<short> audio_buffer;
static int current_sample_rate = 24000;

// Callback функции
static int set_sample_rate_callback(int sample_rate, void* user_data) {
    NSLog(@"🎵 RHVoice sample rate: %d Hz", sample_rate);
    current_sample_rate = sample_rate;
    return 1;
}

static int play_speech_callback(const short* samples, unsigned int count, void* user_data) {
    NSLog(@"🎵 RHVoice audio chunk: %u samples", count);
    for (unsigned int i = 0; i < count; i++) {
        audio_buffer.push_back(samples[i]);
    }
    return 1;
}

static void done_callback(void* user_data) {
    NSLog(@"✅ RHVoice synthesis completed, total samples: %zu", audio_buffer.size());
}

@implementation BundledRHVoiceWrapper

static RHVoice_tts_engine engine = NULL;

+ (void)initializeRHVoice {
    NSLog(@"🔧 Инициализация RHVoice с данными из bundle...");
    
    // Получаем путь к bundle
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *bundlePath = [mainBundle bundlePath];
    NSString *dataPath = [bundlePath stringByAppendingPathComponent:@"data"];
    
    NSLog(@"📁 Bundle path: %@", bundlePath);
    NSLog(@"📁 Data path: %@", dataPath);
    
    // Проверяем существование данных
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:dataPath]) {
        NSLog(@"✅ Данные найдены в bundle");
        
        // Проверяем голоса
        NSString *voicesPath = [dataPath stringByAppendingPathComponent:@"voices"];
        NSArray *voices = [fileManager contentsOfDirectoryAtPath:voicesPath error:nil];
        NSLog(@"🎤 Найдены голоса: %@", voices);
    } else {
        NSLog(@"❌ Данные не найдены в bundle: %@", dataPath);
        return;
    }
    
    // Настройка callbacks
    RHVoice_callbacks callbacks = {0};
    callbacks.set_sample_rate = set_sample_rate_callback;
    callbacks.play_speech = play_speech_callback;
    callbacks.done = done_callback;
    
    // Путь к данным в bundle
    const char* data_path_cstr = [dataPath UTF8String];
    const char* resource_paths[] = {data_path_cstr, NULL};
    
    // Параметры инициализации
    RHVoice_init_params init_params = {0};
    init_params.resource_paths = resource_paths;
    init_params.callbacks = callbacks;
    init_params.options = RHVoice_preload_voices;
    
    NSLog(@"🔧 Создаем RHVoice engine с путем: %s", data_path_cstr);
    
    // Создаем TTS engine
    engine = RHVoice_new_tts_engine(&init_params);
    
    if (engine) {
        NSLog(@"✅ RHVoice TTS engine создан успешно!");
        
        // Проверяем доступные голоса
        unsigned int voice_count = RHVoice_get_number_of_voices(engine);
        NSLog(@"📢 Доступно голосов: %u", voice_count);
        
        const RHVoice_voice_info* voices = RHVoice_get_voices(engine);
        for (unsigned int i = 0; i < voice_count; i++) {
            NSLog(@"🎤 Голос %u: %s (язык: %s)", i, voices[i].name, voices[i].language);
        }
    } else {
        NSLog(@"❌ Не удалось создать RHVoice TTS engine");
    }
}

+ (NSData *)synthesizeText:(NSString *)text withVoice:(NSString *)voiceName {
    NSLog(@"🗣️ RHVoice синтез: '%@' голосом '%@'", text, voiceName);
    
    if (!engine) {
        NSLog(@"❌ RHVoice engine не инициализирован");
        return nil;
    }
    
    // Очищаем буфер
    audio_buffer.clear();
    
    // Параметры синтеза
    RHVoice_synth_params synth_params = {0};
    synth_params.voice_profile = [voiceName UTF8String];
    
    // Создаем сообщение для синтеза
    const char* text_cstr = [text UTF8String];
    RHVoice_message message = RHVoice_new_message(
        engine, 
        text_cstr, 
        strlen(text_cstr), 
        RHVoice_message_text, 
        &synth_params, 
        NULL
    );
    
    if (message) {
        NSLog(@"📝 Сообщение создано, начинаем синтез...");
        
        // Выполняем синтез
        int result = RHVoice_speak(message);
        
        // Освобождаем сообщение
        RHVoice_delete_message(message);
        
        if (result && !audio_buffer.empty()) {
            NSLog(@"✅ Синтез успешен: %zu samples при %d Hz", audio_buffer.size(), current_sample_rate);
            
            // Создаем WAV файл
            NSMutableData *wavData = [NSMutableData data];
            
            // WAV header
            [wavData appendBytes:"RIFF" length:4];
            uint32_t fileSize = 36 + (uint32_t)(audio_buffer.size() * 2);
            [wavData appendBytes:&fileSize length:4];
            [wavData appendBytes:"WAVE" length:4];
            [wavData appendBytes:"fmt " length:4];
            uint32_t fmtSize = 16;
            [wavData appendBytes:&fmtSize length:4];
            uint16_t audioFormat = 1;
            [wavData appendBytes:&audioFormat length:2];
            uint16_t numChannels = 1;
            [wavData appendBytes:&numChannels length:2];
            uint32_t sampleRate = current_sample_rate;
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
            
            // Добавляем аудио данные от RHVoice
            [wavData appendBytes:audio_buffer.data() length:audio_buffer.size() * sizeof(short)];
            
            NSLog(@"📄 WAV файл с НАСТОЯЩЕЙ речью: %lu байт", (unsigned long)[wavData length]);
            return wavData;
            
        } else {
            NSLog(@"❌ RHVoice синтез не удался или нет данных");
            return nil;
        }
    } else {
        NSLog(@"❌ Не удалось создать RHVoice сообщение");
        return nil;
    }
}

@end
