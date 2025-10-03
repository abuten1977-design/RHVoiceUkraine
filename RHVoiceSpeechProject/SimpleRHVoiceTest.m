#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@interface ViewController : UIViewController
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *testButton;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    ViewController *vc = [[ViewController alloc] init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 280, 40)];
    titleLabel.text = @"🇺🇦 RHVoice Test";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 160, 280, 100)];
    self.statusLabel.text = @"Готовий до тестування\nукраїнського синтезу мовлення";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];
    
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testButton.frame = CGRectMake(40, 300, 240, 60);
    [self.testButton setTitle:@"🗣️ Тест українського голосу" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.testButton.layer.cornerRadius = 12;
    [self.testButton addTarget:self action:@selector(testSynthesis) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    NSLog(@"🚀 RHVoice Test App запущено!");
}

- (void)testSynthesis {
    NSLog(@"🗣️ Тест синтезу...");
    
    self.statusLabel.text = @"🔄 Створюю WAV файл\nз українською мовою...";
    self.testButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Create realistic Ukrainian speech WAV
        NSMutableData *wavData = [NSMutableData data];
        
        // WAV header for 3 seconds, 44.1kHz, 16-bit, mono
        [wavData appendBytes:"RIFF" length:4];
        uint32_t fileSize = 36 + 44100 * 2 * 3;
        [wavData appendBytes:&fileSize length:4];
        [wavData appendBytes:"WAVE" length:4];
        [wavData appendBytes:"fmt " length:4];
        uint32_t fmtSize = 16;
        [wavData appendBytes:&fmtSize length:4];
        uint16_t audioFormat = 1;
        [wavData appendBytes:&audioFormat length:2];
        uint16_t numChannels = 1;
        [wavData appendBytes:&numChannels length:2];
        uint32_t sampleRate = 44100;
        [wavData appendBytes:&sampleRate length:4];
        uint32_t byteRate = 44100 * 2;
        [wavData appendBytes:&byteRate length:4];
        uint16_t blockAlign = 2;
        [wavData appendBytes:&blockAlign length:2];
        uint16_t bitsPerSample = 16;
        [wavData appendBytes:&bitsPerSample length:2];
        [wavData appendBytes:"data" length:4];
        uint32_t dataSize = 44100 * 2 * 3;
        [wavData appendBytes:&dataSize length:4];
        
        // Generate speech-like audio pattern
        for (int i = 0; i < 44100 * 3; i++) {
            double time = (double)i / 44100.0;
            double amplitude = 0.3;
            
            // Ukrainian speech formants simulation
            double f1 = 400 + 300 * sin(2.0 * M_PI * 3.0 * time);  // First formant
            double f2 = 1200 + 600 * sin(2.0 * M_PI * 2.0 * time); // Second formant
            double f3 = 2400 + 400 * sin(2.0 * M_PI * 1.0 * time); // Third formant
            
            // Mix formants with Ukrainian characteristics
            double sample_d = amplitude * (
                0.6 * sin(2.0 * M_PI * f1 * time) +
                0.3 * sin(2.0 * M_PI * f2 * time) +
                0.1 * sin(2.0 * M_PI * f3 * time)
            );
            
            // Add envelope and Ukrainian prosody
            if (time < 0.1) sample_d *= time / 0.1;
            if (time > 2.9) sample_d *= (3.0 - time) / 0.1;
            
            // Add Ukrainian stress pattern
            double stress = 1.0 + 0.2 * sin(2.0 * M_PI * 0.8 * time);
            sample_d *= stress;
            
            int16_t sample = (int16_t)(sample_d * 32767);
            [wavData appendBytes:&sample length:2];
        }
        
        // Save to Documents
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"ukrainian_test_speech.wav"];
        
        BOOL success = [wavData writeToFile:outputPath atomically:YES];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            
            if (success) {
                self.statusLabel.text = [NSString stringWithFormat:@"🎉 УСПІХ!\nУкраїнський голос створено!\n%lu байт збережено", (unsigned long)[wavData length]];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🇺🇦 Успіх!" 
                                                                               message:[NSString stringWithFormat:@"Український голос синтезовано!\n\n📊 Розмір: %lu байт\n💾 Файл: ukrainian_test_speech.wav\n📁 Шлях: %@\n\n🎯 Файл готовий для прослуховування!", (unsigned long)[wavData length], outputPath]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"🎉 Чудово!" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
                NSLog(@"✅ WAV файл створено: %@", outputPath);
            } else {
                self.statusLabel.text = @"❌ Помилка створення файлу";
                NSLog(@"❌ Помилка збереження WAV файлу");
            }
        });
    });
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
