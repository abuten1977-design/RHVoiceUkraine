#import <UIKit/UIKit.h>
#import "MinimalRHVoiceWrapper.h"

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
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 280, 40)];
    titleLabel.text = @"RHVoice Ukrainian Test";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 140, 280, 120)];
    self.statusLabel.text = @"Ініціалізація RHVoice...\nЗачекайте";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];
    
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testButton.frame = CGRectMake(40, 300, 240, 60);
    [self.testButton setTitle:@"Український голос!" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.testButton.layer.cornerRadius = 12;
    self.testButton.enabled = NO;
    [self.testButton addTarget:self action:@selector(testSynthesis) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    NSLog(@"RHVoice Ukrainian Test запущено!");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [MinimalRHVoiceWrapper initializeRHVoice];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"RHVoice готовий!\nНатисніть для тесту\nукраїнського синтезу";
            self.testButton.enabled = YES;
        });
    });
}

- (void)testSynthesis {
    NSLog(@"Тест українського синтезу...");
    
    self.statusLabel.text = @"Синтезую українську мову...\nГолос: Наталія";
    self.testButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *ukrainianText = @"Привіт! Це тест українського голосу RHVoice на iPhone! Слава Україні!";
        
        NSData *audioData = [MinimalRHVoiceWrapper synthesizeText:ukrainianText withVoice:@"natalia"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            
            if (audioData && [audioData length] > 0) {
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"ukrainian_voice.wav"];
                
                BOOL success = [audioData writeToFile:outputPath atomically:YES];
                
                self.statusLabel.text = [NSString stringWithFormat:@"УСПІХ!\nУкраїнський голос створено!\n%lu байт збережено", (unsigned long)[audioData length]];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Успіх!" 
                                                                               message:[NSString stringWithFormat:@"Український голос синтезовано!\n%lu байт\nЗбережено як ukrainian_voice.wav\n\nТепер можете слухати українську мову на iPhone!", (unsigned long)[audioData length]]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Чудово!" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                self.statusLabel.text = @"Помилка синтезу";
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
