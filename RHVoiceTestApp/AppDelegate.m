#import "AppDelegate.h"
#import <RHVoiceFramework/RHVoiceFramework.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    // Test RHVoice
    RHVoiceWrapper *wrapper = [[RHVoiceWrapper alloc] init];
    NSLog(@"RHVoice initialized: %@", wrapper ? @"YES" : @"NO");
    
    return YES;
}

@end
