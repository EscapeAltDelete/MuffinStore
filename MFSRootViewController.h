#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface MFSRootViewController : PSListController

- (void)browseVersionsForAppIdentifier:(long long)appIdentifier;

@end
