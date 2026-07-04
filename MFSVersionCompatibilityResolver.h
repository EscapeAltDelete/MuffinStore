#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MFSCompatibilityProgressBlock)(NSDictionary* version, NSString* minimumOSVersion, BOOL compatible);
typedef void (^MFSCompatibilityCompletionBlock)(NSDictionary* _Nullable latestCompatibleVersion,
	NSString* _Nullable minimumOSVersion,
	NSError* _Nullable error);

@interface MFSVersionCompatibilityResolver : NSObject

@property (nonatomic, readonly, copy) NSString* deviceOSVersion;

- (instancetype)initWithAppIdentifier:(long long)appIdentifier versions:(NSArray<NSDictionary*>*)versions;
- (void)startWithProgress:(MFSCompatibilityProgressBlock)progress
	completion:(MFSCompatibilityCompletionBlock)completion;
- (void)cancel;
- (void)clearCachedMetadata;

@end

NS_ASSUME_NONNULL_END
