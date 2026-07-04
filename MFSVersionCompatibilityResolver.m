#import "MFSVersionCompatibilityResolver.h"

#import "MFSAppStoreMetadataClient.h"
#import "MFSRemoteZipReader.h"

#import <UIKit/UIKit.h>

static NSString* const MFSCompatibilityCacheDefaultsKey = @"MFSCompatibilityMetadataCacheV1";

@interface MFSVersionCompatibilityResolver ()

@property (nonatomic) long long appIdentifier;
@property (nonatomic, copy) NSArray<NSDictionary*>* versions;
@property (nonatomic, readwrite, copy) NSString* deviceOSVersion;
@property (nonatomic) MFSAppStoreMetadataClient* metadataClient;
@property (nonatomic) MFSRemoteZipReader* remoteZipReader;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, copy) MFSCompatibilityProgressBlock progressBlock;
@property (nonatomic, copy) MFSCompatibilityCompletionBlock completionBlock;

@end

@implementation MFSVersionCompatibilityResolver

- (instancetype)initWithAppIdentifier:(long long)appIdentifier versions:(NSArray<NSDictionary*>*)versions
{
	self = [super init];
	if (self)
	{
		_appIdentifier = appIdentifier;
		_versions = [versions sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* first, NSDictionary* second)
		{
			long long firstIdentifier = [first[@"external_identifier"] longLongValue];
			long long secondIdentifier = [second[@"external_identifier"] longLongValue];
			if (firstIdentifier > secondIdentifier)
			{
				return NSOrderedAscending;
			}
			if (firstIdentifier < secondIdentifier)
			{
				return NSOrderedDescending;
			}
			return NSOrderedSame;
		}];
		_deviceOSVersion = UIDevice.currentDevice.systemVersion;
		_metadataClient = [MFSAppStoreMetadataClient new];
		_remoteZipReader = [MFSRemoteZipReader new];
	}
	return self;
}

- (NSString*)cacheKeyForVersion:(NSDictionary*)version
{
	return [NSString stringWithFormat:@"%lld:%@", self.appIdentifier, version[@"external_identifier"]];
}

- (NSDictionary*)cachedMetadataForVersion:(NSDictionary*)version
{
	NSString* key = [self cacheKeyForVersion:version];
	@synchronized(NSUserDefaults.standardUserDefaults)
	{
		NSDictionary* cache = [NSUserDefaults.standardUserDefaults dictionaryForKey:MFSCompatibilityCacheDefaultsKey];
		NSDictionary* metadata = cache[key];
		if (![metadata isKindOfClass:NSDictionary.class])
		{
			return nil;
		}

		NSString* expectedDisplayVersion = [NSString stringWithFormat:@"%@", version[@"bundle_version"] ?: @""];
		NSString* cachedDisplayVersion = metadata[@"displayVersion"];
		NSString* minimumOSVersion = metadata[@"minimumOSVersion"];
		if (expectedDisplayVersion.length == 0
			|| ![cachedDisplayVersion isEqualToString:expectedDisplayVersion]
			|| minimumOSVersion.length == 0)
		{
			return nil;
		}
		return metadata;
	}
}

- (void)cacheMinimumOSVersion:(NSString*)minimumOSVersion
	displayVersion:(NSString*)displayVersion
	forVersion:(NSDictionary*)version
{
	NSString* key = [self cacheKeyForVersion:version];
	@synchronized(NSUserDefaults.standardUserDefaults)
	{
		NSDictionary* existing = [NSUserDefaults.standardUserDefaults dictionaryForKey:MFSCompatibilityCacheDefaultsKey];
		NSMutableDictionary* cache = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
		cache[key] = @{
			@"minimumOSVersion": minimumOSVersion,
			@"displayVersion": displayVersion
		};
		[NSUserDefaults.standardUserDefaults setObject:cache forKey:MFSCompatibilityCacheDefaultsKey];
	}
}

- (BOOL)isMinimumOSVersionCompatible:(NSString*)minimumOSVersion
{
	return [minimumOSVersion compare:self.deviceOSVersion options:NSNumericSearch] != NSOrderedDescending;
}

- (void)dispatchProgressForVersion:(NSDictionary*)version
	minimumOSVersion:(NSString*)minimumOSVersion
	compatible:(BOOL)compatible
	generation:(NSUInteger)generation
{
	dispatch_async(dispatch_get_main_queue(), ^
	{
		if (generation == self.generation && self.progressBlock)
		{
			self.progressBlock(version, minimumOSVersion, compatible);
		}
	});
}

- (void)finishWithVersion:(NSDictionary*)version
	minimumOSVersion:(NSString*)minimumOSVersion
	error:(NSError*)error
	generation:(NSUInteger)generation
{
	dispatch_async(dispatch_get_main_queue(), ^
	{
		if (generation != self.generation)
		{
			return;
		}
		if (self.completionBlock)
		{
			self.completionBlock(version, minimumOSVersion, error);
		}
		self.progressBlock = nil;
		self.completionBlock = nil;
	});
}

- (void)resolveVersionAtIndex:(NSUInteger)index generation:(NSUInteger)generation
{
	if (generation != self.generation)
	{
		return;
	}
	if (index >= self.versions.count)
	{
		[self finishWithVersion:nil
			minimumOSVersion:nil
			error:[NSError errorWithDomain:MFSAppStoreMetadataErrorDomain
				code:MFSAppStoreMetadataErrorInvalidResponse
				userInfo:@{NSLocalizedDescriptionKey: @"None of the available historical builds support this device."}]
			generation:generation];
		return;
	}

	NSDictionary* version = self.versions[index];
	NSDictionary* cachedMetadata = [self cachedMetadataForVersion:version];
	if (cachedMetadata)
	{
		NSString* minimumOSVersion = cachedMetadata[@"minimumOSVersion"];
		BOOL compatible = [self isMinimumOSVersionCompatible:minimumOSVersion];
		[self dispatchProgressForVersion:version
			minimumOSVersion:minimumOSVersion
			compatible:compatible
			generation:generation];
		if (compatible)
		{
			[self finishWithVersion:version
				minimumOSVersion:minimumOSVersion
				error:nil
				generation:generation];
		}
		else
		{
			[self resolveVersionAtIndex:index + 1 generation:generation];
		}
		return;
	}

	long long versionIdentifier = [version[@"external_identifier"] longLongValue];
	if (versionIdentifier <= 0)
	{
		NSError* error = [NSError errorWithDomain:MFSAppStoreMetadataErrorDomain
			code:MFSAppStoreMetadataErrorInvalidResponse
			userInfo:@{NSLocalizedDescriptionKey: @"The version history server returned an invalid version identifier."}];
		[self finishWithVersion:nil minimumOSVersion:nil error:error generation:generation];
		return;
	}

	[self.metadataClient resolveDownloadURLForAppIdentifier:self.appIdentifier
		versionIdentifier:versionIdentifier
		completion:^(NSURL* downloadURL, NSError* metadataError)
	{
		if (generation != self.generation)
		{
			return;
		}
		if (metadataError)
		{
			[self finishWithVersion:nil minimumOSVersion:nil error:metadataError generation:generation];
			return;
		}

		[self.remoteZipReader readMainApplicationInfoPlistFromURL:downloadURL
			completion:^(NSDictionary* infoPlist, NSError* ZIPError)
		{
			if (generation != self.generation)
			{
				return;
			}
			if (ZIPError)
			{
				[self finishWithVersion:nil minimumOSVersion:nil error:ZIPError generation:generation];
				return;
			}

			NSString* minimumOSVersion = infoPlist[@"MinimumOSVersion"];
			NSString* displayVersion = infoPlist[@"CFBundleShortVersionString"];
			NSString* expectedDisplayVersion = [NSString stringWithFormat:@"%@", version[@"bundle_version"] ?: @""];
			if (minimumOSVersion.length == 0 || displayVersion.length == 0)
			{
				NSError* error = [NSError errorWithDomain:MFSRemoteZipErrorDomain
					code:1
					userInfo:@{NSLocalizedDescriptionKey: @"The historical build does not declare its version and MinimumOSVersion."}];
				[self finishWithVersion:nil minimumOSVersion:nil error:error generation:generation];
				return;
			}
			if (![displayVersion isEqualToString:expectedDisplayVersion])
			{
				NSString* description = [NSString stringWithFormat:
					@"Apple returned build %@ while checking version %@. Compatibility was not guessed.",
					displayVersion,
					expectedDisplayVersion];
				NSError* error = [NSError errorWithDomain:MFSRemoteZipErrorDomain
					code:1
					userInfo:@{NSLocalizedDescriptionKey: description}];
				[self finishWithVersion:nil minimumOSVersion:nil error:error generation:generation];
				return;
			}

			[self cacheMinimumOSVersion:minimumOSVersion displayVersion:displayVersion forVersion:version];
			BOOL compatible = [self isMinimumOSVersionCompatible:minimumOSVersion];
			[self dispatchProgressForVersion:version
				minimumOSVersion:minimumOSVersion
				compatible:compatible
				generation:generation];
			if (compatible)
			{
				[self finishWithVersion:version
					minimumOSVersion:minimumOSVersion
					error:nil
					generation:generation];
			}
			else
			{
				[self resolveVersionAtIndex:index + 1 generation:generation];
			}
		}];
	}];
}

- (void)startWithProgress:(MFSCompatibilityProgressBlock)progress
	completion:(MFSCompatibilityCompletionBlock)completion
{
	self.generation++;
	self.progressBlock = progress;
	self.completionBlock = completion;
	[self resolveVersionAtIndex:0 generation:self.generation];
}

- (void)cancel
{
	self.generation++;
	self.progressBlock = nil;
	self.completionBlock = nil;
}

- (void)clearCachedMetadata
{
	NSString* prefix = [NSString stringWithFormat:@"%lld:", self.appIdentifier];
	@synchronized(NSUserDefaults.standardUserDefaults)
	{
		NSDictionary* existing = [NSUserDefaults.standardUserDefaults dictionaryForKey:MFSCompatibilityCacheDefaultsKey];
		NSMutableDictionary* cache = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
		for (NSString* key in cache.allKeys)
		{
			if ([key hasPrefix:prefix])
			{
				[cache removeObjectForKey:key];
			}
		}
		[NSUserDefaults.standardUserDefaults setObject:cache forKey:MFSCompatibilityCacheDefaultsKey];
	}
}

@end
