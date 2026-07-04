#import <Foundation/Foundation.h>

@interface SSAccount : NSObject

@property (nonatomic, readonly, copy) NSString* accountName;
@property (nonatomic, readonly, copy) NSString* passwordEquivalentToken;
@property (nonatomic, readonly, copy) NSString* storeFrontIdentifier;
@property (nonatomic, readonly, retain) NSNumber* uniqueIdentifier;

@end

@interface SSAccountStore : NSObject

@property (nonatomic, readonly) SSAccount* activeAccount;

+ (instancetype)defaultStore;

@end
