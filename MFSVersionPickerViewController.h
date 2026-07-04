#import <UIKit/UIKit.h>

typedef void (^MFSVersionPickerCompletion)(NSDictionary* selectedVersion);

@interface MFSVersionPickerViewController : UITableViewController

@property (nonatomic, copy) MFSVersionPickerCompletion completionHandler;

- (instancetype)initWithAppIdentifier:(long long)appIdentifier
	versions:(NSArray*)versions
	completion:(MFSVersionPickerCompletion)completion;

@end
