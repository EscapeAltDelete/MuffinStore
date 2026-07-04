#import "MFSAppStoreMetadataClient.h"
#import "AppleMediaServices.h"
#import "StoreServices.h"

#import <CommonCrypto/CommonDigest.h>

NSString* const MFSAppStoreMetadataErrorDomain = @"dev.mineek.muffinstore.metadata";

@implementation MFSAppStoreMetadataClient

- (NSError*)errorWithCode:(MFSAppStoreMetadataErrorCode)code description:(NSString*)description
{
	return [NSError errorWithDomain:MFSAppStoreMetadataErrorDomain
		code:code
		userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (NSString*)guidForAccountName:(NSString*)accountName
{
	// This is the same stable Configurator-style GUID used by ipatool clients.
	NSString* seed = [NSString stringWithFormat:@"CAFEBABE%@CAFEBABE", accountName];
	NSData* seedData = [seed dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(seedData.bytes, (CC_LONG)seedData.length, digest);

	NSMutableString* hash = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
	for (NSUInteger index = 0; index < CC_SHA1_DIGEST_LENGTH; index++)
	{
		[hash appendFormat:@"%02x", digest[index]];
	}

	NSString* hashPart = [hash substringWithRange:NSMakeRange(10, 10)];
	return [[@"00" stringByAppendingString:hashPart] uppercaseString];
}

- (void)resolveDownloadURLForAppIdentifier:(long long)appIdentifier
	versionIdentifier:(long long)versionIdentifier
	completion:(void (^)(NSURL* downloadURL, NSError* error))completion
{
	SSAccount* account = [SSAccountStore defaultStore].activeAccount;
	if (!account)
	{
		completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorNoAccount
			description:@"Sign in to the App Store before checking historical compatibility."]);
		return;
	}

	NSString* directoryServicesIdentifier = account.uniqueIdentifier.stringValue;
	NSString* accountName = account.accountName ?: directoryServicesIdentifier;
	if (directoryServicesIdentifier.length == 0 || accountName.length == 0)
	{
		completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorAuthenticationUnavailable
			description:@"The current App Store session is missing its account identifier. Open the App Store and sign in again."]);
		return;
	}

	NSString* guid = [self guidForAccountName:accountName];
	NSString* URLString = [NSString stringWithFormat:
		@"https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=%@",
		guid];
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URLString]
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		timeoutInterval:30];
	request.HTTPMethod = @"POST";
	request.allHTTPHeaderFields = @{
		@"Accept": @"*/*",
		@"Content-Type": @"application/x-apple-plist",
		@"User-Agent": @"Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6",
		@"X-Dsid": directoryServicesIdentifier,
		@"iCloud-DSID": directoryServicesIdentifier
	};
	if (account.backingAccount &&
		[request respondsToSelector:@selector(ams_addXTokenHeaderWithAccount:)])
	{
		[request ams_addXTokenHeaderWithAccount:account.backingAccount];
	}
	if ([request valueForHTTPHeaderField:@"X-Token"].length == 0)
	{
		NSString* legacyToken = account.passwordEquivalentToken;
		if (legacyToken.length > 0)
		{
			[request setValue:legacyToken forHTTPHeaderField:@"X-Token"];
		}
	}
	if ([request valueForHTTPHeaderField:@"X-Token"].length == 0)
	{
		completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorAuthenticationUnavailable
			description:@"The current App Store session has no usable purchase token. Open the App Store and sign in again."]);
		return;
	}
	if (account.storeFrontIdentifier.length > 0)
	{
		[request setValue:account.storeFrontIdentifier forHTTPHeaderField:@"X-Apple-Store-Front"];
	}

	NSDictionary* payload = @{
		@"creditDisplay": @"",
		@"guid": guid,
		@"salableAdamId": [NSString stringWithFormat:@"%lld", appIdentifier],
		@"externalVersionId": [NSString stringWithFormat:@"%lld", versionIdentifier]
	};
	NSError* serializationError = nil;
	request.HTTPBody = [NSPropertyListSerialization dataWithPropertyList:payload
		format:NSPropertyListXMLFormat_v1_0
		options:0
		error:&serializationError];
	if (!request.HTTPBody)
	{
		completion(nil, serializationError);
		return;
	}

	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request
		completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
	{
		if (error)
		{
			completion(nil, error);
			return;
		}

		NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
		if (![HTTPResponse isKindOfClass:NSHTTPURLResponse.class] || HTTPResponse.statusCode < 200 || HTTPResponse.statusCode >= 300)
		{
			NSString* description = [NSString stringWithFormat:@"Apple returned HTTP %ld.", (long)HTTPResponse.statusCode];
			completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorServer description:description]);
			return;
		}

		NSError* propertyListError = nil;
		NSDictionary* propertyList = [NSPropertyListSerialization propertyListWithData:data
			options:NSPropertyListImmutable
			format:nil
			error:&propertyListError];
		if (![propertyList isKindOfClass:NSDictionary.class])
		{
			completion(nil, propertyListError ?: [self errorWithCode:MFSAppStoreMetadataErrorInvalidResponse
				description:@"Apple returned an invalid download metadata response."]);
			return;
		}

		NSString* failureType = [NSString stringWithFormat:@"%@", propertyList[@"failureType"] ?: @""];
		NSString* customerMessage = propertyList[@"customerMessage"];
		NSArray* items = propertyList[@"songList"];
		NSUInteger itemCount = [items isKindOfClass:NSArray.class] ? items.count : 0;
		NSLog(@"MFS metadata response: failureType=%@, itemCount=%lu",
			failureType.length > 0 ? failureType : @"none",
			(unsigned long)itemCount);
		if ([failureType isEqualToString:@"9610"])
		{
			completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorLicenseRequired
				description:@"This app must be added to your App Store purchase history before historical builds can be checked."]);
			return;
		}
		if (failureType.length > 0)
		{
			NSString* description = customerMessage.length > 0
				? customerMessage
				: [NSString stringWithFormat:@"Apple rejected the metadata request (%@).", failureType];
			completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorServer description:description]);
			return;
		}

		NSDictionary* item = [items isKindOfClass:NSArray.class] ? items.firstObject : nil;
		NSString* downloadURLString = [item isKindOfClass:NSDictionary.class] ? item[@"URL"] : nil;
		NSURL* downloadURL = downloadURLString.length > 0 ? [NSURL URLWithString:downloadURLString] : nil;
		if (!downloadURL)
		{
			completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorInvalidResponse
				description:@"Apple did not return a download URL for this historical build."]);
			return;
		}

		completion(downloadURL, nil);
	}];
	[task resume];
}

@end
