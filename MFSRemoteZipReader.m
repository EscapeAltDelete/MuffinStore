#import "MFSRemoteZipReader.h"

#import <zlib.h>

NSString* const MFSRemoteZipErrorDomain = @"dev.mineek.muffinstore.remotezip";

static const uint32_t MFSZIPEndOfCentralDirectorySignature = 0x06054b50;
static const uint32_t MFSZIPCentralDirectorySignature = 0x02014b50;
static const uint32_t MFSZIPLocalFileSignature = 0x04034b50;
static const NSUInteger MFSZIPMaximumInfoPlistSize = 1024 * 1024;
static const NSUInteger MFSZIPMaximumCentralDirectorySize = 32 * 1024 * 1024;

static uint16_t MFSReadLittleEndian16(const uint8_t* bytes)
{
	return (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}

static uint32_t MFSReadLittleEndian32(const uint8_t* bytes)
{
	return (uint32_t)bytes[0]
		| ((uint32_t)bytes[1] << 8)
		| ((uint32_t)bytes[2] << 16)
		| ((uint32_t)bytes[3] << 24);
}

@interface MFSRemoteZipEntry : NSObject

@property (nonatomic) uint16_t compressionMethod;
@property (nonatomic) uint32_t compressedSize;
@property (nonatomic) uint32_t uncompressedSize;
@property (nonatomic) uint32_t localHeaderOffset;

@end

@implementation MFSRemoteZipEntry
@end

@implementation MFSRemoteZipReader

- (NSError*)errorWithDescription:(NSString*)description
{
	return [NSError errorWithDomain:MFSRemoteZipErrorDomain
		code:1
		userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)contentLengthForURL:(NSURL*)URL completion:(void (^)(long long length, NSError* error))completion
{
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		timeoutInterval:30];
	request.HTTPMethod = @"HEAD";
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request
		completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
	{
		if (error)
		{
			completion(0, error);
			return;
		}

		NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
		long long length = HTTPResponse.expectedContentLength;
		if (length > 0)
		{
			completion(length, nil);
			return;
		}

		[self contentLengthUsingRangeRequestForURL:URL completion:completion];
	}];
	[task resume];
}

- (void)contentLengthUsingRangeRequestForURL:(NSURL*)URL completion:(void (^)(long long length, NSError* error))completion
{
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		timeoutInterval:30];
	[request setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"];
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request
		completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
	{
		if (error)
		{
			completion(0, error);
			return;
		}

		NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
		NSString* contentRange = [HTTPResponse valueForHTTPHeaderField:@"Content-Range"];
		NSRange slashRange = [contentRange rangeOfString:@"/" options:NSBackwardsSearch];
		long long length = slashRange.location != NSNotFound
			? [[contentRange substringFromIndex:slashRange.location + 1] longLongValue]
			: 0;
		if (HTTPResponse.statusCode != 206 || length <= 0)
		{
			completion(0, [self errorWithDescription:@"The App Store download server does not support metadata range requests."]);
			return;
		}
		completion(length, nil);
	}];
	[task resume];
}

- (void)fetchURL:(NSURL*)URL
	rangeFrom:(long long)start
	to:(long long)end
	completion:(void (^)(NSData* data, NSError* error))completion
{
	if (start < 0 || end < start)
	{
		completion(nil, [self errorWithDescription:@"An invalid IPA byte range was requested."]);
		return;
	}

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:URL
		cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		timeoutInterval:30];
	[request setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", start, end] forHTTPHeaderField:@"Range"];
	NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request
		completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
	{
		if (error)
		{
			completion(nil, error);
			return;
		}

		NSHTTPURLResponse* HTTPResponse = (NSHTTPURLResponse*)response;
		long long requestedLength = end - start + 1;
		if (HTTPResponse.statusCode != 206 || (long long)data.length != requestedLength)
		{
			NSString* description = [NSString stringWithFormat:
				@"The App Store returned an invalid IPA byte range (HTTP %ld).",
				(long)HTTPResponse.statusCode];
			completion(nil, [self errorWithDescription:description]);
			return;
		}
		completion(data, nil);
	}];
	[task resume];
}

- (BOOL)isMainApplicationInfoPlistPath:(NSString*)path
{
	NSArray<NSString*>* components = [path componentsSeparatedByString:@"/"];
	return components.count == 3
		&& [components[0] isEqualToString:@"Payload"]
		&& [components[1] hasSuffix:@".app"]
		&& [components[2] isEqualToString:@"Info.plist"];
}

- (MFSRemoteZipEntry*)entryForMainInfoPlistInCentralDirectory:(NSData*)centralDirectory
{
	const uint8_t* bytes = centralDirectory.bytes;
	NSUInteger offset = 0;
	while (offset + 46 <= centralDirectory.length)
	{
		if (MFSReadLittleEndian32(bytes + offset) != MFSZIPCentralDirectorySignature)
		{
			return nil;
		}

		uint16_t fileNameLength = MFSReadLittleEndian16(bytes + offset + 28);
		uint16_t extraLength = MFSReadLittleEndian16(bytes + offset + 30);
		uint16_t commentLength = MFSReadLittleEndian16(bytes + offset + 32);
		NSUInteger recordLength = 46 + fileNameLength + extraLength + commentLength;
		if (offset + recordLength > centralDirectory.length)
		{
			return nil;
		}

		NSData* nameData = [centralDirectory subdataWithRange:NSMakeRange(offset + 46, fileNameLength)];
		NSString* path = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
		if ([self isMainApplicationInfoPlistPath:path])
		{
			MFSRemoteZipEntry* entry = [MFSRemoteZipEntry new];
			entry.compressionMethod = MFSReadLittleEndian16(bytes + offset + 10);
			entry.compressedSize = MFSReadLittleEndian32(bytes + offset + 20);
			entry.uncompressedSize = MFSReadLittleEndian32(bytes + offset + 24);
			entry.localHeaderOffset = MFSReadLittleEndian32(bytes + offset + 42);
			return entry;
		}

		offset += recordLength;
	}
	return nil;
}

- (NSData*)decompressedData:(NSData*)compressedData
	method:(uint16_t)method
	expectedLength:(NSUInteger)expectedLength
	error:(NSError**)error
{
	if (expectedLength == 0 || expectedLength > MFSZIPMaximumInfoPlistSize)
	{
		if (error)
		{
			*error = [self errorWithDescription:@"The IPA contains an invalidly sized Info.plist."];
		}
		return nil;
	}

	if (method == 0)
	{
		if (compressedData.length != expectedLength)
		{
			if (error)
			{
				*error = [self errorWithDescription:@"The uncompressed Info.plist size does not match its ZIP metadata."];
			}
			return nil;
		}
		return compressedData;
	}

	if (method != 8)
	{
		if (error)
		{
			*error = [self errorWithDescription:[NSString stringWithFormat:
				@"The IPA uses unsupported ZIP compression method %u.", method]];
		}
		return nil;
	}

	NSMutableData* output = [NSMutableData dataWithLength:expectedLength];
	z_stream stream = {0};
	stream.next_in = (Bytef*)compressedData.bytes;
	stream.avail_in = (uInt)compressedData.length;
	stream.next_out = output.mutableBytes;
	stream.avail_out = (uInt)output.length;

	int status = inflateInit2(&stream, -MAX_WBITS);
	if (status == Z_OK)
	{
		status = inflate(&stream, Z_FINISH);
		inflateEnd(&stream);
	}
	if (status != Z_STREAM_END || stream.total_out != expectedLength)
	{
		if (error)
		{
			*error = [self errorWithDescription:@"The IPA Info.plist could not be decompressed."];
		}
		return nil;
	}
	return output;
}

- (void)readEntry:(MFSRemoteZipEntry*)entry
	fromURL:(NSURL*)URL
	completion:(void (^)(NSDictionary* infoPlist, NSError* error))completion
{
	if (entry.compressedSize == 0 || entry.compressedSize > MFSZIPMaximumInfoPlistSize)
	{
		completion(nil, [self errorWithDescription:@"The IPA contains an invalid Info.plist entry."]);
		return;
	}

	long long localHeaderOffset = entry.localHeaderOffset;
	[self fetchURL:URL rangeFrom:localHeaderOffset to:localHeaderOffset + 29 completion:^(NSData* localHeader, NSError* error)
	{
		if (error)
		{
			completion(nil, error);
			return;
		}

		const uint8_t* bytes = localHeader.bytes;
		if (localHeader.length != 30 || MFSReadLittleEndian32(bytes) != MFSZIPLocalFileSignature)
		{
			completion(nil, [self errorWithDescription:@"The IPA contains an invalid local ZIP header."]);
			return;
		}

		uint16_t fileNameLength = MFSReadLittleEndian16(bytes + 26);
		uint16_t extraLength = MFSReadLittleEndian16(bytes + 28);
		long long dataOffset = localHeaderOffset + 30 + fileNameLength + extraLength;
		long long dataEnd = dataOffset + entry.compressedSize - 1;
		[self fetchURL:URL rangeFrom:dataOffset to:dataEnd completion:^(NSData* compressedData, NSError* rangeError)
		{
			if (rangeError)
			{
				completion(nil, rangeError);
				return;
			}

			NSError* decompressionError = nil;
			NSData* propertyListData = [self decompressedData:compressedData
				method:entry.compressionMethod
				expectedLength:entry.uncompressedSize
				error:&decompressionError];
			if (!propertyListData)
			{
				completion(nil, decompressionError);
				return;
			}

			NSError* propertyListError = nil;
			NSDictionary* infoPlist = [NSPropertyListSerialization propertyListWithData:propertyListData
				options:NSPropertyListImmutable
				format:nil
				error:&propertyListError];
			if (![infoPlist isKindOfClass:NSDictionary.class])
			{
				completion(nil, propertyListError ?: [self errorWithDescription:@"The IPA Info.plist is invalid."]);
				return;
			}
			completion(infoPlist, nil);
		}];
	}];
}

- (void)readMainApplicationInfoPlistFromURL:(NSURL*)URL
	completion:(void (^)(NSDictionary* infoPlist, NSError* error))completion
{
	[self contentLengthForURL:URL completion:^(long long length, NSError* error)
	{
		if (error)
		{
			completion(nil, error);
			return;
		}

		long long tailLength = MIN(length, 131072);
		long long tailOffset = length - tailLength;
		[self fetchURL:URL rangeFrom:tailOffset to:length - 1 completion:^(NSData* tail, NSError* rangeError)
		{
			if (rangeError)
			{
				completion(nil, rangeError);
				return;
			}

			const uint8_t* bytes = tail.bytes;
			NSInteger endOffset = -1;
			for (NSInteger index = (NSInteger)tail.length - 22; index >= 0; index--)
			{
				if (MFSReadLittleEndian32(bytes + index) == MFSZIPEndOfCentralDirectorySignature)
				{
					endOffset = index;
					break;
				}
			}
			if (endOffset < 0)
			{
				completion(nil, [self errorWithDescription:@"The IPA ZIP directory could not be located."]);
				return;
			}

			uint32_t centralDirectorySize = MFSReadLittleEndian32(bytes + endOffset + 12);
			uint32_t centralDirectoryOffset = MFSReadLittleEndian32(bytes + endOffset + 16);
			if (centralDirectorySize == UINT32_MAX || centralDirectoryOffset == UINT32_MAX)
			{
				completion(nil, [self errorWithDescription:@"ZIP64 IPA metadata is not currently supported."]);
				return;
			}
			if (centralDirectorySize == 0 || centralDirectorySize > MFSZIPMaximumCentralDirectorySize
				|| (long long)centralDirectoryOffset + centralDirectorySize > length)
			{
				completion(nil, [self errorWithDescription:@"The IPA central ZIP directory is invalid."]);
				return;
			}

			void (^handleCentralDirectory)(NSData*) = ^(NSData* centralDirectory)
			{
				MFSRemoteZipEntry* entry = [self entryForMainInfoPlistInCentralDirectory:centralDirectory];
				if (!entry)
				{
					completion(nil, [self errorWithDescription:@"The IPA does not contain a main application Info.plist."]);
					return;
				}
				[self readEntry:entry fromURL:URL completion:completion];
			};

			long long centralEnd = (long long)centralDirectoryOffset + centralDirectorySize;
			if (centralDirectoryOffset >= tailOffset && centralEnd <= length)
			{
				NSRange range = NSMakeRange((NSUInteger)(centralDirectoryOffset - tailOffset), centralDirectorySize);
				handleCentralDirectory([tail subdataWithRange:range]);
				return;
			}

			[self fetchURL:URL
				rangeFrom:centralDirectoryOffset
				to:centralEnd - 1
				completion:^(NSData* centralDirectory, NSError* centralError)
			{
				if (centralError)
				{
					completion(nil, centralError);
					return;
				}
				handleCentralDirectory(centralDirectory);
			}];
		}];
	}];
}

@end
