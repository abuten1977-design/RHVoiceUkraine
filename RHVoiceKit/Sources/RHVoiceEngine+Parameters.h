//
//  RHVoiceEngine+Parameters.h
//  PolishVariant
//
//  Extension для поддержки расширенных параметров
//

#import "RHVoiceEngine.h"

@interface RHVoiceEngine (Parameters)

/**
 Синтез текста с расширенными параметрами.
 
 @param text Текст для синтеза
 @param voiceName Имя голоса
 @param rate Скорость речи (0.1 - 4.0)
 @param volume Громкость (0.0 - 1.0)
 @param pitch Высота тона (0.5 - 2.0)
 @param pauseDuration Множитель пауз (0.2 - 3.0)
 @return AVAudioPCMBuffer с аудио данными
 */
- (AVAudioPCMBuffer *)synthesize:(NSString *)text
                           voice:(NSString *)voiceName
                            rate:(double)rate
                          volume:(double)volume
                           pitch:(double)pitch
                   pauseDuration:(double)pauseDuration;

@end
