#import <UIKit/UIKit.h>
#import "SimpleRHVoiceStub.h"

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
    titleLabel.text = @"RHVoice iPhone Test";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    // Status
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 140, 280, 120)];
    self.statusLabel.text = @"Ініціалізація RHVoice...\nЗачекайте";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];
    
    // Test button
    self.testButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.testButton.frame = CGRectMake(40, 300, 240, 60);
    [self.testButton setTitle:@"Тест українського голосу!" forState:UIControlStateNormal];
    self.testButton.backgroundColor = [UIColor systemBlueColor];
    [self.testButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.testButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.testButton.layer.cornerRadius = 12;
    self.testButton.enabled = NO;
    [self.testButton addTarget:self action:@selector(synthesizeSpeech) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    NSLog(@"RHVoice iPhone Test запущено!");
    
    // Initialize RHVoice
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [RHVoiceStub initializeRHVoice];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"RHVoice готовий!\nНатисніть кнопку для\nтесту синтезу мови";
            self.testButton.enabled = YES;
        });
    });
}

- (void)synthesizeSpeech {
    NSLog(@"Початок тесту синтезу...");
    
    self.statusLabel.text = @"Синтезую тестовий звук...\n(440Hz тон)";
    self.testButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *testText = @"Привіт! Це тест українського голосу на iPhone!";
        
        NSData *audioData = [RHVoiceStub synthesizeText:testText withVoice:@"natalia"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            
            if (audioData && [audioData length] > 0) {
                // Save to Documents
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"rhvoice_test.wav"];
                
                BOOL success = [audioData writeToFile:outputPath atomically:YES];
                
                self.statusLabel.text = [NSString stringWithFormat:@"УСПІХ!\n%lu байт згенеровано\nrhvoice_test.wav збережено", (unsigned long)[audioData length]];
                
                // Show success alert
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Тест пройшов успішно!" 
                                                                               message:[NSString stringWithFormat:@"Аудіо файл створено!\n%lu байт\nЗбережено в Documents як rhvoice_test.wav\n\nЦе тестовий тон 440Hz.\nНаступний крок: справжній RHVoice!", (unsigned long)[audioData length]]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Чудово!" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                self.statusLabel.text = @"Помилка створення аудіо";
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
