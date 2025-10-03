#import <UIKit/UIKit.h>
#import "TrueRHVoiceWrapper.mm"

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
    titleLabel.text = @"🇺🇦 TRUE RHVoice Ukrainian";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 110, 280, 60)];
    self.statusLabel.text = @"Ініціалізація СПРАВЖНЬОГО\nRHVoice TTS...";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];
    
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testButton.frame = CGRectMake(40, 190, 240, 50);
    [self.testButton setTitle:@"🗣️ СПРАВЖНІЙ синтез!" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.testButton.layer.cornerRadius = 10;
    self.testButton.enabled = NO;
    [self.testButton addTarget:self action:@selector(testRealSynthesis) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 260, 280, 320)];
    self.logView.backgroundColor = [UIColor systemGray6Color];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.logView.editable = NO;
    self.logView.text = @"=== СПРАВЖНІЙ RHVoice Log ===\n";
    [self.view addSubview:self.logView];
    
    NSLog(@"🚀 TRUE RHVoice App запущено!");
    [self addLog:@"🚀 Додаток запущено"];
    
    // Инициализация настоящего RHVoice
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self addLog:@"⚙️ Ініціалізація СПРАВЖНЬОГО RHVoice..."];
        [TrueRHVoiceWrapper initializeRHVoice];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"✅ СПРАВЖНІЙ RHVoice готовий!\nНатисніть для тесту";
            self.testButton.enabled = YES;
            [self addLog:@"✅ СПРАВЖНІЙ RHVoice ініціалізовано"];
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
        
        NSRange bottom = NSMakeRange([self.logView.text length] - 1, 1);
        [self.logView scrollRangeToVisible:bottom];
    });
}

- (void)testRealSynthesis {
    NSLog(@"🗣️ Тест СПРАВЖНЬОГО українського синтезу...");
    [self addLog:@"🗣️ СПРАВЖНІЙ синтез почався"];
    
    self.statusLabel.text = @"🔄 СПРАВЖНІЙ RHVoice\nсинтезує українську мову...";
    self.testButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *voices = @[@"natalia", @"marianna", @"volodymyr", @"anatol"];
        NSArray *texts = @[
            @"Привіт! Це справжній голос Наталії від RHVoice. Слава Україні!",
            @"Вітаю! Маріанна говорить справжньою українською мовою!", 
            @"Доброго дня! Володимир використовує справжній RHVoice TTS!",
            @"Здоровенькі були! Анатолій синтезує справжню українську мову!"
        ];
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        
        int successCount = 0;
        
        for (int i = 0; i < voices.count; i++) {
            NSString *voice = voices[i];
            NSString *text = texts[i];
            
            [self addLog:[NSString stringWithFormat:@"🎤 СПРАВЖНІЙ синтез: %@", voice]];
            
            NSData *audioData = [TrueRHVoiceWrapper synthesizeText:text withVoice:voice];
            
            if (audioData && [audioData length] > 0) {
                NSString *filename = [NSString stringWithFormat:@"true_ukrainian_%@.wav", voice];
                NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:filename];
                
                BOOL success = [audioData writeToFile:outputPath atomically:YES];
                
                if (success) {
                    successCount++;
                    [self addLog:[NSString stringWithFormat:@"✅ СПРАВЖНІЙ %@: %lu байт", voice, (unsigned long)[audioData length]]];
                } else {
                    [self addLog:[NSString stringWithFormat:@"❌ %@: помилка збереження", voice]];
                }
            } else {
                [self addLog:[NSString stringWithFormat:@"❌ %@: помилка СПРАВЖНЬОГО синтезу", voice]];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            
            if (successCount > 0) {
                self.statusLabel.text = [NSString stringWithFormat:@"🎉 СПРАВЖНІЙ УСПІХ!\n%d українських голосів\nвід RHVoice TTS", successCount];
                [self addLog:[NSString stringWithFormat:@"🎉 СПРАВЖНІЙ УСПІХ: %d голосів!", successCount]];
            } else {
                self.statusLabel.text = @"❌ Помилка СПРАВЖНЬОГО синтезу";
                [self addLog:@"❌ СПРАВЖНІЙ синтез не вдався"];
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
