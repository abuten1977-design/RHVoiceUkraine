#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (strong, nonatomic) UITextView *textView;
@property (strong, nonatomic) UIButton *synthesizeButton;
@property (strong, nonatomic) UILabel *statusLabel;

- (IBAction)synthesizeButtonTapped:(id)sender;

@end
