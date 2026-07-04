#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const MFSRemoteZipErrorDomain;

@interface MFSRemoteZipReader : NSObject

- (void)readMainApplicationInfoPlistFromURL:(NSURL*)URL
	completion:(void (^)(NSDictionary* _Nullable infoPlist, NSError* _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
