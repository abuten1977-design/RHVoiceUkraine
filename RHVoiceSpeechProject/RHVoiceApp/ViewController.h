#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UIButton *synthesizeButton;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;

- (IBAction)synthesizeButtonTapped:(id)sender;

@end
