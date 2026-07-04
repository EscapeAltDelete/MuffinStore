#import "MFSAppDelegate.h"
#import "MFSRootViewController.h"

@implementation MFSAppDelegate

- (BOOL)openVersionsURL:(NSURL*)url
{
	if (![[url.scheme lowercaseString] isEqualToString:@"muffinstore"] ||
		![[url.host lowercaseString] isEqualToString:@"versions"])
	{
		return NO;
	}

	NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSString* appIdentifierValue = nil;
	for (NSURLQueryItem* item in components.queryItems)
	{
		if ([item.name isEqualToString:@"appId"])
		{
			appIdentifierValue = item.value;
			break;
		}
	}

	long long appIdentifier = appIdentifierValue.longLongValue;
	MFSRootViewController* rootViewController =
		(MFSRootViewController*)self.rootViewController.viewControllers.firstObject;
	[rootViewController browseVersionsForAppIdentifier:appIdentifier];
	return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	_window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	_rootViewController = [[UINavigationController alloc] initWithRootViewController:[[MFSRootViewController alloc] init]];
	_window.rootViewController = _rootViewController;
	[_window makeKeyAndVisible];
	return YES;
}

- (BOOL)application:(UIApplication*)application
	openURL:(NSURL*)url
	options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options
{
	return [self openVersionsURL:url];
}

@end
