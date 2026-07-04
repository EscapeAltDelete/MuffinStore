#import <Foundation/Foundation.h>

@class ACAccount;

@interface ACAccount (MFSAppleMediaServices)

- (NSArray<NSHTTPCookie*>*)ams_cookiesForURL:(NSURL*)URL;

@end

@interface NSMutableURLRequest (MFSAppleMediaServices)

- (void)ams_addXTokenHeaderWithAccount:(ACAccount*)account;

@end
