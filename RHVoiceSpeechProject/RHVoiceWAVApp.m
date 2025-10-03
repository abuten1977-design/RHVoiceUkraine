#import <UIKit/UIKit.h>
#import "RHVoiceEngine/include/RHVoiceWrapper.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@interface ViewController : UIViewController
@property (strong, nonatomic) UILabel *statusLabel;
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
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 280, 200)];
    self.statusLabel.text = @"RHVoice WAV Test\nInitializing...\nPlease wait";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.statusLabel];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(50, 350, 220, 50);
    [button setTitle:@"Synthesize Speech" forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemBlueColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 8;
    [button addTarget:self action:@selector(synthesizeSpeech) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    
    NSLog(@"RHVoice WAV App loaded!");
    
    // Initialize RHVoice in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"Initializing RHVoice...");
        [RHVoiceWrapper initializeRHVoice];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"RHVoice Ready!\nPress button to\nsynthesize speech";
            NSLog(@"RHVoice initialization complete!");
        });
    });
}

- (void)synthesizeSpeech {
    NSLog(@"Starting speech synthesis...");
    self.statusLabel.text = @"Synthesizing...\nПривіт! Це тест";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *testText = @"Привіт! Це тест українського голосу.";
        NSLog(@"Text to synthesize: %@", testText);
        
        NSData *audioData = [RHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (audioData && [audioData length] > 0) {
                NSLog(@"✅ Synthesis SUCCESS! %lu bytes", (unsigned long)[audioData length]);
                
                // Save to Documents
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                NSString *documentsDirectory = [paths objectAtIndex:0];
                NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"rhvoice_output.wav"];
                
                BOOL success = [audioData writeToFile:outputPath atomically:YES];
                NSLog(@"File save: %@ at %@", success ? @"SUCCESS" : @"FAILED", outputPath);
                
                self.statusLabel.text = [NSString stringWithFormat:@"✅ SUCCESS!\n%lu bytes\nSaved as rhvoice_output.wav", (unsigned long)[audioData length]];
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" 
                                                                               message:[NSString stringWithFormat:@"Ukrainian speech synthesized!\n%lu bytes saved to Documents", (unsigned long)[audioData length]]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                NSLog(@"❌ Synthesis FAILED - no audio data");
                self.statusLabel.text = @"❌ FAILED\nNo audio generated\nCheck console";
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
