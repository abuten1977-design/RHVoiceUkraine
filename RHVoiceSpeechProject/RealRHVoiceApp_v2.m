#import <UIKit/UIKit.h>
#import "RHVoiceEngine/include/RHVoiceWrapper.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@interface ViewController : UIViewController
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *testButton;
@property (strong, nonatomic) UITextView *logView;
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
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, 280, 40)];
    titleLabel.text = @"🇺🇦 RHVoice Ukrainian TTS";
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 110, 280, 80)];
    self.statusLabel.text = @"Ініціалізація RHVoice...\nЗачекайте";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];
    
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testButton.frame = CGRectMake(40, 210, 240, 50);
    [self.testButton setTitle:@"🗣️ Синтез українською!" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.testButton.layer.cornerRadius = 10;
    self.testButton.enabled = NO;
    [self.testButton addTarget:self action:@selector(testSynthesis) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    // Log view for debugging
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 280, 280, 300)];
    self.logView.backgroundColor = [UIColor systemGray6Color];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:10];
    self.logView.editable = NO;
    self.logView.text = @"=== RHVoice Log ===\n";
    [self.view addSubview:self.logView];
    
    NSLog(@"🚀 RHVoice Ukrainian TTS App запущено!");
    [self addLog:@"🚀 Додаток запущено"];
    
    // Initialize RHVoice in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self addLog:@"⚙️ Ініціалізація RHVoice..."];
        [RHVoiceWrapper initializeRHVoice];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"✅ RHVoice готовий!\nНатисніть для тесту\nукраїнського синтезу";
            self.testButton.enabled = YES;
            [self addLog:@"✅ RHVoice ініціалізовано"];
        });
    });
}

- (void)addLog:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                             dateStyle:NSDateFormatterNoStyle 
                                                             timeStyle:NSDateFormatterMediumStyle];
        NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
        self.logView.text = [self.logView.text stringByAppendingString:logEntry];
        
        // Scroll to bottom
        NSRange bottom = NSMakeRange([self.logView.text length] - 1, 1);
        [self.logView scrollRangeToVisible:bottom];
    });
}

- (void)testSynthesis {
    NSLog(@"🗣️ Тест українського синтезу...");
    [self addLog:@"🗣️ Початок синтезу"];
    
    self.statusLabel.text = @"🔄 Синтезую українську мову...\nГолос: Наталія";
    self.testButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *ukrainianText = @"Привіт! Це тест українського голосу RHVoice на iPhone! Слава Україні! Героям слава!";
        [self addLog:[NSString stringWithFormat:@"📝 Текст: %@", ukrainianText]];
        
        NSData *audioData = [RHVoiceWrapper synthesizeText:ukrainianText withVoice:@"natalia"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            
            if (audioData && [audioData length] > 0) {
                [self addLog:[NSString stringWithFormat:@"✅ Синтез успішний: %lu байт", (unsigned long)[audioData length]]];
                
                // Save to Documents
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"ukrainian_voice_real.wav"];
                
                BOOL success = [audioData writeToFile:outputPath atomically:YES];
                [self addLog:[NSString stringWithFormat:@"💾 Файл збережено: %@", success ? @"ТАК" : @"НІ"]];
                [self addLog:[NSString stringWithFormat:@"📁 Шлях: %@", outputPath]];
                
                self.statusLabel.text = [NSString stringWithFormat:@"🎉 УСПІХ!\nУкраїнський голос створено!\n%lu байт збережено", (unsigned long)[audioData length]];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🇺🇦 Успіх!" 
                                                                               message:[NSString stringWithFormat:@"Український голос синтезовано!\n\n📊 Розмір: %lu байт\n💾 Файл: ukrainian_voice_real.wav\n\n🎯 Тепер можете слухати українську мову на iPhone!", (unsigned long)[audioData length]]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"🎉 Чудово!" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                [self addLog:@"❌ Помилка синтезу"];
                self.statusLabel.text = @"❌ Помилка синтезу\nПеревірте логи";
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"❌ Помилка" 
                                                                               message:@"Не вдалося синтезувати українську мову. Перевірте логи для деталей."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
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
