#import <UIKit/UIKit.h>
#import "FixedRHVoiceWrapper.mm"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@interface ViewController : UIViewController
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
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, 280, 200)];
    label.text = @"🇺🇦 ФИНАЛЬНЫЙ ТЕСТ\nНАСТОЯЩЕГО RHVoice\nПроверьте логи...";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:18];
    [self.view addSubview:label];
    
    NSLog(@"🚀 ФИНАЛЬНЫЙ тест НАСТОЯЩЕГО RHVoice!");
    
    // Автоматический тест через 2 секунды
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runFinalTest];
    });
}

- (void)runFinalTest {
    NSLog(@"🔧 ФИНАЛЬНЫЙ тест НАСТОЯЩЕГО RHVoice...");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Инициализация
        [FixedRHVoiceWrapper initializeRHVoice];
        
        // Тест синтеза украинского текста
        NSString *testText = @"Привіт! Це справжній тест RHVoice українською мовою.";
        NSData *audioData = [FixedRHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
        
        if (audioData && [audioData length] > 0) {
            NSLog(@"✅ НАСТОЯЩИЙ синтез успешен: %lu байт", (unsigned long)[audioData length]);
            
            // Сохраняем файл
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"final_real_rhvoice.wav"];
            
            BOOL success = [audioData writeToFile:outputPath atomically:YES];
            NSLog(@"💾 НАСТОЯЩИЙ файл сохранен: %@ в %@", success ? @"ДА" : @"НЕТ", outputPath);
            
            if (success) {
                NSLog(@"🎉 УСПЕХ! Создан НАСТОЯЩИЙ украинский голос от RHVoice!");
            }
        } else {
            NSLog(@"❌ НАСТОЯЩИЙ синтез не удался");
        }
    });
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
