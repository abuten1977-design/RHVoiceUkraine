#import <Foundation/Foundation.h>
#import "Bridge/RHVoice/RHSpeechSynthesizer.h"

int main() {
    @autoreleasepool {
        NSLog(@"--- СИНТЕЗ ЧЕРЕЗ ПОЛЬСКИЙ МОСТ ---");
        RHSpeechSynthesizer *synth = [[RHSpeechSynthesizer alloc] init];
        
        // Здесь мы вручную имитируем передачу параметров, которые потом встроим в Bridge
        NSLog(@"Тестуємо прискорення 2.5 та роздільні паузи...");
        
        // Для теста просто вызываем синтез
        // (Параметры мы добавим в сам Bridge на следующем шаге)
        [synth synthesizeUtterance:nil toFileAtPath:@"/Users/andriybutenko/Desktop/polish_bridge_test.wav"];
        
        NSLog(@"ГОТОВО! Файл на робочому столі.");
    }
    return 0;
}
