#import <UIKit/UIKit.h>

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
    self.view.backgroundColor = [UIColor whiteColor];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 280, 200)];
    label.text = @"WAV File Test\nCreating test audio file\nCheck Documents folder";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:label];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(50, 350, 220, 50);
    [button setTitle:@"Create WAV File" forState:UIControlStateNormal];
    button.backgroundColor = [UIColor systemGreenColor];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 8;
    [button addTarget:self action:@selector(createWAVFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    
    NSLog(@"WAV Test App loaded successfully!");
}

- (void)createWAVFile {
    NSLog(@"Creating test WAV file...");
    
    // Create simple WAV file with silence (44.1kHz, 16-bit, mono, 1 second)
    NSMutableData *wavData = [NSMutableData data];
    
    // WAV header
    [wavData appendBytes:"RIFF" length:4];
    uint32_t fileSize = 36 + 44100 * 2; // header + data
    [wavData appendBytes:&fileSize length:4];
    [wavData appendBytes:"WAVE" length:4];
    [wavData appendBytes:"fmt " length:4];
    uint32_t fmtSize = 16;
    [wavData appendBytes:&fmtSize length:4];
    uint16_t audioFormat = 1; // PCM
    [wavData appendBytes:&audioFormat length:2];
    uint16_t numChannels = 1; // mono
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
    uint32_t dataSize = 44100 * 2;
    [wavData appendBytes:&dataSize length:4];
    
    // Add 1 second of silence (zeros)
    NSMutableData *silenceData = [NSMutableData dataWithLength:44100 * 2];
    [wavData appendData:silenceData];
    
    // Save to Documents
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"test_silence.wav"];
    
    BOOL success = [wavData writeToFile:outputPath atomically:YES];
    NSLog(@"WAV file creation: %@ at %@", success ? @"SUCCESS" : @"FAILED", outputPath);
    NSLog(@"File size: %lu bytes", (unsigned long)[wavData length]);
    
    if (success) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" 
                                                                       message:[NSString stringWithFormat:@"WAV file created!\n%lu bytes\nSaved to Documents", (unsigned long)[wavData length]]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
