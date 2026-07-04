#import <Foundation/Foundation.h>

@class ACAccount;

@interface SSAccount : NSObject

@property (nonatomic, readonly) ACAccount* backingAccount;
@property (nonatomic, readonly, copy) NSString* passwordEquivalentToken;
@property (nonatomic, readonly, copy) NSString* storeFrontIdentifier;
@property (nonatomic, readonly, retain) NSNumber* uniqueIdentifier;

@end

@interface SSAccountStore : NSObject

@property (nonatomic, readonly) SSAccount* activeAccount;

+ (instancetype)defaultStore;

@end

@interface SSDevice : NSObject

@property (nonatomic, readonly, copy) NSString* uniqueDeviceIdentifier;

+ (instancetype)currentDevice;

@end
