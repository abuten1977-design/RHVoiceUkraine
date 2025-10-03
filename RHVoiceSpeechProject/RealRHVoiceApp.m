#import <UIKit/UIKit.h>
#import "RHVoiceEngine/include/RHVoiceWrapper.h"

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
    
    // Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 280, 40)];
    titleLabel.text = @"REAL RHVoice Test";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    // Status
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 140, 280, 120)];
    self.statusLabel.text = @"Ініціалізація СПРАВЖНЬОГО RHVoice...\nЗачекайте";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];
    
    // Test button
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testButton.frame = CGRectMake(40, 300, 240, 60);
    [self.testButton setTitle:@"СПРАВЖНІЙ український голос!" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemGreenColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.testButton.layer.cornerRadius = 12;
    self.testButton.enabled = NO;
    [self.testButton addTarget:self action:@selector(synthesizeRealSpeech) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    NSLog(@"REAL RHVoice App запущено!");
    
    // Initialize REAL RHVoice
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"Ініціалізація СПРАВЖНЬОГО RHVoice...");
        [RHVoiceWrapper initializeRHVoice];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"СПРАВЖНІЙ RHVoice готовий!\nНатисніть для синтезу\nукраїнської мови";
            self.testButton.enabled = YES;
            NSLog(@"СПРАВЖНІЙ RHVoice ініціалізовано!");
        });
    });
}

- (void)synthesizeRealSpeech {
    NSLog(@"Початок СПРАВЖНЬОГО синтезу української мови...");
    
    self.statusLabel.text = @"Синтезую СПРАВЖНЮ\nукраїнську мову...\nГолос: Наталія";
    self.testButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *testText = @"Привіт! Це справжній український голос RHVoice на iPhone! Слава Україні!";
        NSLog(@"Синтез тексту: %@", testText);
        
        NSData *audioData = [RHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            
            if (audioData && [audioData length] > 0) {
                NSLog(@"УСПІХ! СПРАВЖНІЙ синтез завершено: %lu байт", (unsigned long)[audioData length]);
                
                // Save to Documents
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"real_ukrainian_speech.wav"];
                
                BOOL success = [audioData writeToFile:outputPath atomically:YES];
                NSLog(@"Збереження: %@ в %@", success ? @"УСПІХ" : @"ПОМИЛКА", outputPath);
                
                self.statusLabel.text = [NSString stringWithFormat:@"УСПІХ!\nСПРАВЖНІЙ український голос!\n%lu байт\nreal_ukrainian_speech.wav", (unsigned long)[audioData length]];
                
                // Show success alert
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"УСПІХ!" 
                                                                               message:[NSString stringWithFormat:@"СПРАВЖНІЙ український голос синтезовано!\n%lu байт збережено\nГолос: Наталія\nМова: Українська", (unsigned long)[audioData length]]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Слава Україні!" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                NSLog(@"ПОМИЛКА: СПРАВЖНІЙ синтез не вдався");
                self.statusLabel.text = @"ПОМИЛКА\nСинтез не вдався\nПеревірте консоль";
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Помилка" 
                                                                               message:@"Синтез не вдався.\nПеревірте консоль для деталей."
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
