//
//  RHVoiceEngine+Parameters.mm
//  PolishVariant
//
//  Покращена реалізація параметрів (паузи через SSML strength)
//

#import "RHVoiceEngine+Parameters.h"

@implementation RHVoiceEngine (Parameters)

- (AVAudioPCMBuffer *)synthesize:(NSString *)text
                           voice:(NSString *)voiceName
                            rate:(double)rate
                          volume:(double)volume
                           pitch:(double)pitch
                   pauseDuration:(double)pauseDuration {
    
    // 1. Попередня обробка тексту для реалізації пауз
    NSString *processedText = text;
    
    // Якщо множник пауз не стандартний, додаємо SSML теги з відповідною силою (strength)
    if (pauseDuration != 1.0) {
        NSString *strength = @"medium";
        
        if (pauseDuration < 0.5) {
            strength = @"x-weak";
        } else if (pauseDuration < 0.8) {
            strength = @"weak";
        } else if (pauseDuration > 1.5) {
            strength = @"strong";
        } else if (pauseDuration > 2.0) {
            strength = @"x-strong";
        }
        
        NSString *pauseTag = [NSString stringWithFormat:@" <break strength='%@'/> ", strength];
        
        // Додаємо паузу після основних знаків пунктуації
        processedText = [processedText stringByReplacingOccurrencesOfString:@"." withString:[@"." stringByAppendingString:pauseTag]];
        processedText = [processedText stringByReplacingOccurrencesOfString:@"," withString:[@"," stringByAppendingString:pauseTag]];
        processedText = [processedText stringByReplacingOccurrencesOfString:@"!" withString:[@"!" stringByAppendingString:pauseTag]];
        processedText = [processedText stringByReplacingOccurrencesOfString:@"?" withString:[@"?" stringByAppendingString:pauseTag]];
        
        // Обертаємо весь текст в SSML тег speak для підтримки <break>
        processedText = [NSString stringWithFormat:@"<speak>%@</speak>", processedText];
    }
    
    // 2. Виклик основного методу синтезу
    // УВАГА: RHVoiceEngine повинен підтримувати RHVoice_message_ssml (ми це додали)
    return [self synthesize:processedText
                      voice:voiceName
                       rate:rate
                     volume:volume
                      pitch:pitch];
}

@end
