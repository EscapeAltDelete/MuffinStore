#import <Foundation/Foundation.h>

@class ACAccount;

@interface NSMutableURLRequest (MFSAppleMediaServices)

- (void)ams_addXTokenHeaderWithAccount:(ACAccount*)account;

@end
