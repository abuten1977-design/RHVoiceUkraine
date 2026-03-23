#import <Foundation/Foundation.h>
#import "RHSpeechSynthesizer.h"

int main() {
    @autoreleasepool {
        RHSpeechSynthesizer *synth = [[RHSpeechSynthesizer alloc] init];
        NSString *text = @"Привіт, це тест швидкості та пауз.";
        
        printf("--- ТЕСТ 1: НОРМАЛЬНАЯ СКОРОСТЬ ---\n");
        [synth say:text toFile:@"1_normal.wav"];
        
        printf("--- ТЕСТ 2: ТУРБО-СКОРОСТЬ (Multiplier 2.0) ---\n");
        [synth setParam:@"rate" value:200];
        [synth say:text toFile:@"2_turbo.wav"];
        
        printf("--- ТЕСТ 3: ПАУЗЫ (1000ms) ---\n");
        [synth setParam:@"pause_duration" value:1000];
        [synth say:text toFile:@"3_pauses.wav"];
        
        printf("--- СИНТЕЗ ГОТОВ. ФАЙЛЫ СОЗДАНЫ. ---\n");
    }
    return 0;
}
