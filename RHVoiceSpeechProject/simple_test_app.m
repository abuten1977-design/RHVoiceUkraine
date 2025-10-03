#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "RHVoiceEngine/include/RHVoiceWrapper.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"App started - testing RHVoice...");
    
    // Initialize RHVoice
    [RHVoiceWrapper initializeRHVoice];
    NSLog(@"RHVoice initialized");
    
    // Test synthesis
    NSString *testText = @"Привіт! Це тест українського голосу.";
    NSLog(@"Testing text: %@", testText);
    
    NSData *audioData = [RHVoiceWrapper synthesizeText:testText withVoice:@"natalia"];
    if (audioData) {
        NSLog(@"Audio synthesis successful! Generated %lu bytes", (unsigned long)[audioData length]);
        
        // Save to Documents directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:@"test_output.wav"];
        
        BOOL success = [audioData writeToFile:outputPath atomically:YES];
        NSLog(@"Audio saved to %@: %@", outputPath, success ? @"SUCCESS" : @"FAILED");
        
        if (success) {
            NSLog(@"You can find the audio file at: %@", outputPath);
        }
    } else {
        NSLog(@"Audio synthesis failed!");
    }
    
    // Create simple UI
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIViewController *viewController = [[UIViewController alloc] init];
    viewController.view.backgroundColor = [UIColor whiteColor];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 280, 200)];
    label.text = audioData ? @"RHVoice test SUCCESS!\nCheck console for details." : @"RHVoice test FAILED!\nCheck console for errors.";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [viewController.view addSubview:label];
    
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
