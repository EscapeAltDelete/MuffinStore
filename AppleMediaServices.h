#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ACAccount : NSObject
@end

@interface ACAccount (MFSAppleMediaServices)

- (nullable NSArray<NSHTTPCookie*>*)ams_cookiesForURL:(NSURL*)URL;

@end

@interface NSMutableURLRequest (MFSAppleMediaServices)

- (void)ams_addXTokenHeaderWithAccount:(ACAccount*)account;

@end

@interface AMSProcessInfo : NSObject

+ (instancetype)currentProcess;

@end

@interface AMSAuthenticateOptions : NSObject

@property (nonatomic) BOOL allowServerDialogs;
@property (nonatomic) NSUInteger authenticationType;
@property (nonatomic) BOOL canMakeAccountActive;
@property (nonatomic) NSUInteger credentialSource;
@property (nonatomic, strong) AMSProcessInfo* clientInfo;
@property (nonatomic, copy) NSString* debugReason;

- (void)setPresentingViewController:(id)viewController;

@end

@interface AMSAuthenticateResult : NSObject

@property (nonatomic, readonly, nullable) ACAccount* account;

@end

@interface AMSPromise : NSObject

- (void)addFinishBlock:(void (^)(id _Nullable result, NSError* _Nullable error))block;

@end

@interface AMSAuthenticateTask : NSObject

- (instancetype)initWithAccount:(ACAccount*)account options:(AMSAuthenticateOptions*)options;
- (AMSPromise*)performAuthentication;

@end

NS_ASSUME_NONNULL_END
