#import "MFSAppStoreMetadataClient.h"
#import "AppleMediaServices.h"
#import "StoreServices.h"

#import <UIKit/UIKit.h>

NSString* const MFSAppStoreMetadataErrorDomain = @"dev.mineek.muffinstore.metadata";

@interface MFSAppStoreMetadataClient ()

- (NSError*)errorWithCode:(MFSAppStoreMetadataErrorCode)code description:(NSString*)description;
- (NSError*)authenticationErrorWithUnderlyingError:(NSError* _Nullable)underlyingError;
- (UIViewController* _Nullable)authenticationPresenter;
- (NSString*)commerceHostForAccount:(ACAccount* _Nullable)account;
- (NSMutableURLRequest* _Nullable)requestForAppIdentifier:(long long)appIdentifier
	versionIdentifier:(long long)versionIdentifier
	account:(SSAccount*)account
	backingAccount:(ACAccount* _Nullable)backingAccount
	error:(NSError**)error;
- (void)refreshAuthenticationForAccount:(ACAccount* _Nullable)account
	completion:(void (^)(ACAccount* _Nullable account, NSError* _Nullable error))completion;
- (BOOL)isAuthenticationFailureType:(NSString*)failureType;
- (void)resolveDownloadURLForAppIdentifier:(long long)appIdentifier
	versionIdentifier:(long long)versionIdentifier
	account:(SSAccount*)account
	backingAccount:(ACAccount* _Nullable)backingAccount
	allowAuthenticationRetry:(BOOL)allowAuthenticationRetry
	completion:(void (^)(NSURL* _Nullable downloadURL, NSError* _Nullable error))completion;

@end

@implementation MFSAppStoreMetadataClient

- (NSError*)errorWithCode:(MFSAppStoreMetadataErrorCode)code description:(NSString*)description
{
	return [NSError errorWithDomain:MFSAppStoreMetadataErrorDomain
		code:code
		userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (NSError*)authenticationErrorWithUnderlyingError:(NSError*)underlyingError
{
	NSMutableDictionary* userInfo = [@{
		NSLocalizedDescriptionKey: @"App Store authentication could not be completed. Open the App Store, sign in, and try again."
	} mutableCopy];
	if (underlyingError)
	{
		userInfo[NSUnderlyingErrorKey] = underlyingError;
	}
	return [NSError errorWithDomain:MFSAppStoreMetadataErrorDomain
		code:MFSAppStoreMetadataErrorAuthenticationUnavailable
		userInfo:userInfo];
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

	[self resolveDownloadURLForAppIdentifier:appIdentifier
		versionIdentifier:versionIdentifier
		account:account
		backingAccount:account.backingAccount
		allowAuthenticationRetry:YES
		completion:completion];
}

- (NSMutableURLRequest*)requestForAppIdentifier:(long long)appIdentifier
	versionIdentifier:(long long)versionIdentifier
	account:(SSAccount*)account
	backingAccount:(ACAccount*)backingAccount
	error:(NSError**)error
{
	NSString* directoryServicesIdentifier = account.uniqueIdentifier.stringValue;
	if (directoryServicesIdentifier.length == 0)
	{
		if (error)
		{
			*error = [self errorWithCode:MFSAppStoreMetadataErrorAuthenticationUnavailable
			description:@"The current App Store session is missing its account identifier. Open the App Store and sign in again."];
		}
		return nil;
	}

	NSString* guid = [SSDevice currentDevice].uniqueDeviceIdentifier;
	if (guid.length == 0)
	{
		if (error)
		{
			*error = [self errorWithCode:MFSAppStoreMetadataErrorAuthenticationUnavailable
				description:@"The device identifier required by the App Store is unavailable."];
		}
		return nil;
	}

	NSString* commerceHost = [self commerceHostForAccount:backingAccount];
	NSString* URLString = [NSString stringWithFormat:
		@"https://%@/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=%@",
		commerceHost,
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
	if (backingAccount)
	{
		NSString* refreshedToken = [backingAccount ams_password];
		if (refreshedToken.length > 0)
		{
			[request setValue:refreshedToken forHTTPHeaderField:@"X-Token"];
		}
		else
		{
			[request ams_addXTokenHeaderWithAccount:backingAccount];
		}
		NSArray<NSHTTPCookie*>* cookies = [backingAccount ams_cookiesForURL:request.URL];
		NSLog(@"MFS metadata request: host=%@, cookieCount=%lu, tokenPresent=%@",
			request.URL.host,
			(unsigned long)cookies.count,
			[request valueForHTTPHeaderField:@"X-Token"].length > 0 ? @"yes" : @"no");
		NSDictionary<NSString*, NSString*>* cookieHeaders =
			[NSHTTPCookie requestHeaderFieldsWithCookies:cookies ?: @[]];
		for (NSString* header in cookieHeaders)
		{
			[request setValue:cookieHeaders[header] forHTTPHeaderField:header];
		}
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
		if (error)
		{
			*error = serializationError;
		}
		return nil;
	}
	return request;
}

- (NSString*)commerceHostForAccount:(ACAccount*)account
{
	if (!account)
	{
		return @"buy.itunes.apple.com";
	}

	NSURL* commerceURL = [NSURL URLWithString:@"https://buy.itunes.apple.com/"];
	NSArray<NSHTTPCookie*>* cookies = [account ams_cookiesForURL:commerceURL];
	NSCharacterSet* nonDecimalDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
	for (NSHTTPCookie* cookie in cookies)
	{
		if ([cookie.name caseInsensitiveCompare:@"itspod"] != NSOrderedSame)
		{
			continue;
		}

		NSString* pod = cookie.value;
		if (pod.length > 0 && [pod rangeOfCharacterFromSet:nonDecimalDigits].location == NSNotFound)
		{
			return [NSString stringWithFormat:@"p%@-buy.itunes.apple.com", pod];
		}
	}
	return @"buy.itunes.apple.com";
}

- (UIViewController*)authenticationPresenter
{
	UIWindow* selectedWindow = nil;
	for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
	{
		if (scene.activationState != UISceneActivationStateForegroundActive ||
			![scene isKindOfClass:UIWindowScene.class])
		{
			continue;
		}

		UIWindowScene* windowScene = (UIWindowScene*)scene;
		for (UIWindow* window in windowScene.windows)
		{
			if (window.isKeyWindow)
			{
				selectedWindow = window;
				break;
			}
			if (!selectedWindow && !window.hidden)
			{
				selectedWindow = window;
			}
		}
		if (selectedWindow)
		{
			break;
		}
	}

	UIViewController* presenter = selectedWindow.rootViewController;
	while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)
	{
		presenter = presenter.presentedViewController;
	}
	return presenter;
}

- (void)refreshAuthenticationForAccount:(ACAccount*)account
	completion:(void (^)(ACAccount* account, NSError* error))completion
{
	if (!account)
	{
		completion(nil, [self authenticationErrorWithUnderlyingError:nil]);
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^
	{
		AMSAuthenticateOptions* options = [AMSAuthenticateOptions new];
		options.allowServerDialogs = YES;
		options.authenticationType = 0; // Silent preferred; use the system dialog only if required.
		options.canMakeAccountActive = NO;
		options.credentialSource = 2;
		options.clientInfo = [AMSProcessInfo currentProcess];
		options.debugReason = @"MuffinStore compatibility metadata";

		UIViewController* presenter = [self authenticationPresenter];
		if (presenter)
		{
			[options setPresentingViewController:presenter];
		}

		AMSAuthenticateTask* task = [[AMSAuthenticateTask alloc] initWithAccount:account options:options];
		AMSPromise* promise = [task performAuthentication];
		if (!task || !promise)
		{
			completion(nil, [self authenticationErrorWithUnderlyingError:nil]);
			return;
		}
		[promise addFinishBlock:^(AMSAuthenticateResult* result, NSError* authenticationError)
		{
			(void)task;
			if (authenticationError)
			{
				completion(nil, [self authenticationErrorWithUnderlyingError:authenticationError]);
				return;
			}

			ACAccount* refreshedAccount = [result respondsToSelector:@selector(account)]
				? result.account
				: nil;
			completion(refreshedAccount ?: account, nil);
		}];
	});
}

- (BOOL)isAuthenticationFailureType:(NSString*)failureType
{
	return [failureType isEqualToString:@"1008"]
		|| [failureType isEqualToString:@"2034"]
		|| [failureType isEqualToString:@"2042"];
}

- (void)resolveDownloadURLForAppIdentifier:(long long)appIdentifier
	versionIdentifier:(long long)versionIdentifier
	account:(SSAccount*)account
	backingAccount:(ACAccount*)backingAccount
	allowAuthenticationRetry:(BOOL)allowAuthenticationRetry
	completion:(void (^)(NSURL* downloadURL, NSError* error))completion
{
	NSError* requestError = nil;
	NSMutableURLRequest* request = [self requestForAppIdentifier:appIdentifier
		versionIdentifier:versionIdentifier
		account:account
		backingAccount:backingAccount
		error:&requestError];
	if (!request)
	{
		completion(nil, requestError);
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
		NSLog(@"MFS metadata response: failureType=%@, itemCount=%lu, tokenAccepted=%@",
			failureType.length > 0 ? failureType : @"none",
			(unsigned long)itemCount,
			[HTTPResponse valueForHTTPHeaderField:@"Apple-Tk"] ?: @"unknown");
		if ([self isAuthenticationFailureType:failureType] && allowAuthenticationRetry)
		{
			[self refreshAuthenticationForAccount:backingAccount
				completion:^(ACAccount* refreshedAccount, NSError* authenticationError)
			{
				if (authenticationError)
				{
					completion(nil, authenticationError);
					return;
				}
				[self resolveDownloadURLForAppIdentifier:appIdentifier
					versionIdentifier:versionIdentifier
					account:account
					backingAccount:refreshedAccount
					allowAuthenticationRetry:NO
					completion:completion];
			}];
			return;
		}
		if ([self isAuthenticationFailureType:failureType])
		{
			completion(nil, [self errorWithCode:MFSAppStoreMetadataErrorAuthenticationUnavailable
				description:@"Apple requires App Store authentication before historical builds can be checked."]);
			return;
		}
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
