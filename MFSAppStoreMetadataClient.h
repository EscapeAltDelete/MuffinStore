#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const MFSAppStoreMetadataErrorDomain;

typedef NS_ENUM(NSInteger, MFSAppStoreMetadataErrorCode)
{
	MFSAppStoreMetadataErrorNoAccount = 1,
	MFSAppStoreMetadataErrorAuthenticationUnavailable,
	MFSAppStoreMetadataErrorInvalidResponse,
	MFSAppStoreMetadataErrorLicenseRequired,
	MFSAppStoreMetadataErrorServer
};

@interface MFSAppStoreMetadataClient : NSObject

- (void)resolveDownloadURLForAppIdentifier:(long long)appIdentifier
	versionIdentifier:(long long)versionIdentifier
	completion:(void (^)(NSURL* _Nullable downloadURL, NSError* _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
