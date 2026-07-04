#import <Foundation/Foundation.h>

@interface ACAccount : NSObject
@end

@interface ACAccount (MFSAppleMediaServices)

- (NSArray<NSHTTPCookie*>*)ams_cookiesForURL:(NSURL*)URL;

@end

@interface NSMutableURLRequest (MFSAppleMediaServices)

- (void)ams_addXTokenHeaderWithAccount:(ACAccount*)account;

@end
