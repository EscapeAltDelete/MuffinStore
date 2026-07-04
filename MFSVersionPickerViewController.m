#import "MFSVersionPickerViewController.h"
#import "MFSVersionCompatibilityResolver.h"

@interface MFSVersionPickerViewController ()

@property (nonatomic) long long appIdentifier;
@property (nonatomic, strong) NSArray* versions;
@property (nonatomic) MFSVersionCompatibilityResolver* compatibilityResolver;
@property (nonatomic) NSMutableDictionary<NSString*, NSString*>* minimumOSVersions;
@property (nonatomic, copy) NSString* latestCompatibleIdentifier;
@property (nonatomic, copy) NSString* compatibilityStatus;
@property (nonatomic) BOOL compatibilityCheckStarted;

@end

@implementation MFSVersionPickerViewController

- (instancetype)initWithAppIdentifier:(long long)appIdentifier
	versions:(NSArray*)versions
	completion:(MFSVersionPickerCompletion)completion
{
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self)
	{
		_appIdentifier = appIdentifier;
		_versions = [versions copy];
		_completionHandler = completion;
		_minimumOSVersions = [NSMutableDictionary dictionary];
		_compatibilityResolver = [[MFSVersionCompatibilityResolver alloc]
			initWithAppIdentifier:appIdentifier
			versions:versions];
		_compatibilityStatus = [NSString stringWithFormat:
			@"Checking the newest builds against iOS %@…",
			_compatibilityResolver.deviceOSVersion];
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"Select Version";
	UIBarButtonItem* cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelTapped)];
	self.navigationItem.leftBarButtonItem = cancelButton;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
		target:self
		action:@selector(refreshCompatibility)];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if (!self.compatibilityCheckStarted)
	{
		[self startCompatibilityCheck];
	}
}

- (void)cancelTapped
{
	[self.compatibilityResolver cancel];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString*)identifierForVersion:(NSDictionary*)version
{
	return [NSString stringWithFormat:@"%@", version[@"external_identifier"]];
}

- (NSIndexPath*)indexPathForVersion:(NSDictionary*)version
{
	NSString* identifier = [self identifierForVersion:version];
	NSUInteger index = [self.versions indexOfObjectPassingTest:^BOOL(NSDictionary* candidate, NSUInteger candidateIndex, BOOL* stop)
	{
		return [[self identifierForVersion:candidate] isEqualToString:identifier];
	}];
	return index == NSNotFound ? nil : [NSIndexPath indexPathForRow:index inSection:0];
}

- (void)startCompatibilityCheck
{
	self.compatibilityCheckStarted = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	self.latestCompatibleIdentifier = nil;
	__weak typeof(self) weakSelf = self;
	[self.compatibilityResolver startWithProgress:^(NSDictionary* version, NSString* minimumOSVersion, BOOL compatible)
	{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self)
		{
			return;
		}
		self.minimumOSVersions[[self identifierForVersion:version]] = minimumOSVersion;
		NSIndexPath* indexPath = [self indexPathForVersion:version];
		if (indexPath)
		{
			[self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
		}
	} completion:^(NSDictionary* latestCompatibleVersion, NSString* minimumOSVersion, NSError* error)
	{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self)
		{
			return;
		}
		self.navigationItem.rightBarButtonItem.enabled = YES;
		if (latestCompatibleVersion)
		{
			self.latestCompatibleIdentifier = [self identifierForVersion:latestCompatibleVersion];
			self.compatibilityStatus = [NSString stringWithFormat:
				@"Latest compatible with iOS %@: %@ (requires iOS %@ or later)",
				self.compatibilityResolver.deviceOSVersion,
				latestCompatibleVersion[@"bundle_version"],
				minimumOSVersion];
			NSIndexPath* indexPath = [self indexPathForVersion:latestCompatibleVersion];
			if (indexPath)
			{
				[self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
			}
		}
		else
		{
			self.compatibilityStatus = [NSString stringWithFormat:@"Compatibility check unavailable: %@",
				error.localizedDescription ?: @"Unknown error"];
		}
		[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
	}];
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)refreshCompatibility
{
	[self.compatibilityResolver cancel];
	[self.compatibilityResolver clearCachedMetadata];
	[self.minimumOSVersions removeAllObjects];
	self.latestCompatibleIdentifier = nil;
	self.compatibilityStatus = [NSString stringWithFormat:
		@"Checking the newest builds against iOS %@…",
		self.compatibilityResolver.deviceOSVersion];
	[self startCompatibilityCheck];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return self.versions.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"VersionCell"];
	if (!cell)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"VersionCell"];
	}
	NSDictionary* version = self.versions[indexPath.row];
	cell.textLabel.text = version[@"bundle_version"];
	cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
	NSString* identifier = [self identifierForVersion:version];
	NSString* minimumOSVersion = self.minimumOSVersions[identifier];
	BOOL isLatestCompatible = [identifier isEqualToString:self.latestCompatibleIdentifier];
	if (isLatestCompatible)
	{
		cell.detailTextLabel.text = [NSString stringWithFormat:
			@"Latest for iOS %@ · Requires iOS %@+",
			self.compatibilityResolver.deviceOSVersion,
			minimumOSVersion];
		cell.detailTextLabel.textColor = UIColor.systemGreenColor;
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}
	else if (minimumOSVersion)
	{
		cell.detailTextLabel.text = [NSString stringWithFormat:@"Requires iOS %@+", minimumOSVersion];
		cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	else
	{
		cell.detailTextLabel.text = @"Compatibility not checked";
		cell.detailTextLabel.textColor = UIColor.tertiaryLabelColor;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary* selected = self.versions[indexPath.row];
	[self dismissViewControllerAnimated:YES completion:^
	{
		if (self.completionHandler)
		{
			self.completionHandler(selected);
		}
	}];
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
	return [NSString stringWithFormat:@"%lu versions available", (unsigned long)self.versions.count];
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section
{
	return self.compatibilityStatus;
}

- (void)dealloc
{
	[self.compatibilityResolver cancel];
}

@end
