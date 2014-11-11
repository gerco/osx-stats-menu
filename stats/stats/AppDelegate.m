//
//  AppDelegate.m
//  stats
//
//  Created by Emiel Lensink on 31/12/13.
//  Copyright (c) 2013 Emiel Lensink. All rights reserved.
//

#import "AppDelegate.h"

#import <mach/mach.h>
#import <mach/mach_error.h>
#import <sys/sysctl.h>
#import <unistd.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/storage/IOBlockStorageDriver.h>

#import "AppleSMC/SMCSensors.h"

#import "MenuGraphView.h"

#define DRIVE_READ (1 << 1)
#define DRIVE_WRITE (1 << 2)

// Very slow timer is used for CPU and Temperature measurements
// Slow timer is used for DISK, while disk is mostly idle. Once disk changes,
// fast timer is used until disk goes idle again.

#define VERY_SLOW_TIMER 3.0
#define SLOW_TIMER 1.0
#define FAST_TIMER 0.3

@interface AppDelegate ()
{
	mach_port_t        		masterPort;
	IONotificationPortRef	notifyPort;
	CFRunLoopSourceRef		notifyRunSource;
	io_iterator_t			blockDevicePublishedIterator, blockDeviceTerminatedIterator, blockDeviceIterator;
	UInt64 previousTotalRead, previousTotalWrite;
	UInt64 previousTotalRead3Seconds, previousTotalWrite3Seconds;
	CFTimeInterval absoluteTime3Seconds;
	
	processor_info_array_t	cpuInfo, prevCpuInfo;
	mach_msg_type_number_t	numCpuInfo, numPrevCpuInfo;
	unsigned int			numCPUs;
	
	SMCSensors				*sensors;
	BOOL					enableCPUMonitoring;
	NSArray					*cpuKeys;
}

@property (nonatomic, assign) NSInteger driveActivity;
@property (nonatomic, assign) NSInteger cpuActivity;
@property (nonatomic, assign) NSInteger cpuTemperature;

@property (nonatomic, strong) NSTimer *diskTimer;
@property (nonatomic, strong) NSTimer *cpuTimer;
@property (nonatomic, strong) NSTimer *temperatureTimer;

@property (nonatomic, strong) NSStatusItem *diskStatusItem;
@property (nonatomic, strong) NSImage *diskStatusImage;

@property (nonatomic, strong) NSStatusItem *cpuStatusItem;
@property (nonatomic, strong) NSImage *cpuStatusImage;

@property (nonatomic, strong) NSStatusItem *cpuTemperatureStatusItem;
@property (nonatomic, strong) NSImage *cpuTemperatureStatusImage;

@property (nonatomic, strong) NSDictionary *cpuAttributes3Digits;
@property (nonatomic, strong) NSDictionary *cpuAttributes2Digits;
@property (nonatomic, strong) NSDictionary *cpuAttributes3DigitsAlpha;
@property (nonatomic, strong) NSDictionary *cpuAttributes2DigitsAlpha;

@property (nonatomic, strong) NSMutableArray *driveActivities;
@property (nonatomic, strong) NSMutableArray *cpuActivities;
@property (nonatomic, strong) NSMutableArray *cpuTemperatures;

@property (nonatomic, assign) BOOL isYosemite;
@property (nonatomic, assign) BOOL isMetric;		// For temperature

- (void)blockDeviceChanged:(io_iterator_t)iterator;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Are we running on yosemite?
	{
		BOOL oldVersion = (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_9);
		if (!oldVersion) self.isYosemite = YES;
		else self.isYosemite = NO;
	}
	
	self.isMetric = [[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue];
	
	self.driveActivities = [NSMutableArray array];
	self.cpuActivities = [NSMutableArray array];
	self.cpuTemperatures = [NSMutableArray array];
	
	[self setupStatusItem];
	[self setupBlockDeviceNotifications];
	[self setupCPUActivity];
	[self setupTemperature];
	
	self.diskTimer = [NSTimer timerWithTimeInterval:SLOW_TIMER target:self selector:@selector(updateIO:) userInfo:nil repeats:YES];
	self.cpuTimer = [NSTimer timerWithTimeInterval:VERY_SLOW_TIMER target:self selector:@selector(updateCPU:) userInfo:nil repeats:YES];
	if (enableCPUMonitoring)
	{
		self.temperatureTimer = [NSTimer timerWithTimeInterval:VERY_SLOW_TIMER target:self selector:@selector(updateTemperature:) userInfo:nil repeats:YES];
		[[NSRunLoop mainRunLoop] addTimer:self.temperatureTimer forMode:NSRunLoopCommonModes];
	}
	
	[[NSRunLoop mainRunLoop] addTimer:self.diskTimer forMode:NSRunLoopCommonModes];
	[[NSRunLoop mainRunLoop] addTimer:self.cpuTimer forMode:NSRunLoopCommonModes];
	
	[self addObserver:self forKeyPath:@"driveActivity" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:nil];
	[self addObserver:self forKeyPath:@"cpuActivity" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:nil];
	[self addObserver:self forKeyPath:@"cpuTemperature" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:nil];
	
	

	SMCSensors *sns = [[SMCSensors alloc] init];

	
	[[sns allValues] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		NSLog(@"All Key: %@ (%@), Value: %@", key, [sns humanReadableNameForKey:key], obj);
	}];
		
	[[sns fanValues] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
		NSLog(@"Fan Key: %@ (%@), Value: %@", key, [sns humanReadableNameForKey:key], obj);
		
		[obj enumerateKeysAndObjectsUsingBlock:^(id key2, id obj2, BOOL *stop) {
			NSLog(@"Fan Key: %@ (%@), Value: %@", key2, [sns humanReadableNameForKey:key2], obj2);
		}];
	}];

	
	// Temperature senor values
	// withUnknownSensors: include sensors where humanReadableNameForKey will fail
	// return an NSDictionary with key: SMCSensorName, value: NSNumber with tdegree emperature in Celsius
		
	[[sns temperatureValuesExtended:YES] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		NSLog(@"Temp Key: %@ (%@), Value: %@", key, [sns humanReadableNameForKey:key], obj);
	}];
	
	// additional sensors (motion etc.).
	NSLog(@"%@", [sns sensorValues]);
	

}

- (void)quit
{
    NSApplication *application = [NSApplication sharedApplication];
    
    [self.diskTimer invalidate];
    [self.cpuTimer invalidate];
    [self.temperatureTimer invalidate];
    
    [[NSStatusBar systemStatusBar] removeStatusItem:self.diskStatusItem];
    [[NSStatusBar systemStatusBar] removeStatusItem:self.cpuStatusItem];
    [[NSStatusBar systemStatusBar] removeStatusItem:self.cpuTemperatureStatusItem];
    
    [application terminate:self];
}

- (void)about
{
	NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
	NSString *appName = infoDict[@"CFBundleName"];
	NSString *appVersion = infoDict[@"CFBundleShortVersionString"];
	NSString *appCopyright = infoDict[@"NSHumanReadableCopyright"];
	
	NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"%@ %@", appName, appVersion] defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@\n\n%@", appCopyright, @"http://qixis.com/stats"];

	[alert runModal];
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"driveActivity"])
		[self drawDriveActivity];
	
	if ([keyPath isEqualToString:@"cpuActivity"])
		[self drawCPUActivity];
	
	if ([keyPath isEqualToString:@"cpuTemperature"])
		[self drawCPUTemperature];
}

#pragma mark Initialization of status item
- (void)setupStatusItem
{
	CGFloat height = [[NSStatusBar systemStatusBar] thickness];
    CGFloat cpuWidth = floor(height * 1.2);
	
	self.diskStatusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
	self.diskStatusImage = [[NSImage alloc] initWithSize:NSMakeSize(height, height)];
	
	[self.diskStatusItem setHighlightMode:YES];
	[self.diskStatusItem setImage:self.diskStatusImage];

	self.cpuStatusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:cpuWidth];
	self.cpuStatusImage = [[NSImage alloc] initWithSize:NSMakeSize(cpuWidth, height)];
	
	[self.cpuStatusItem setHighlightMode:YES];
	[self.cpuStatusItem setImage:self.cpuStatusImage];

	self.cpuTemperatureStatusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:cpuWidth];
	self.cpuTemperatureStatusImage = [[NSImage alloc] initWithSize:NSMakeSize(cpuWidth, height)];
	
	[self.cpuTemperatureStatusItem setHighlightMode:YES];
	[self.cpuTemperatureStatusItem setImage:self.cpuTemperatureStatusImage];
	
	// On yosemite, make images templates so they render well in dark mode.
	if (self.isYosemite)
	{
		[self.cpuStatusImage setTemplate:YES];
		[self.cpuTemperatureStatusImage setTemplate:YES];
		[self.diskStatusImage setTemplate:YES];
	}
	
	// Add menu to our status items...
	{
		MenuGraphView *cpuGraphView = [[MenuGraphView alloc] initWithFrame:CGRectMake(0, 0, 300, 70)];
		NSMenuItem *cpuGraphItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
		cpuGraphItem.view = cpuGraphView;

		cpuGraphView.dataSource = self.cpuActivities;
		cpuGraphView.graphRange = NSMakeRange(0, 100);
		cpuGraphView.fillGraph = YES;
		cpuGraphView.isTemplate = self.isYosemite;
		cpuGraphView.graphColor = self.isYosemite ? [NSColor whiteColor] : [NSColor blackColor];
		
		MenuGraphView *temperatureGraphView = [[MenuGraphView alloc] initWithFrame:CGRectMake(0, 0, 300, 70)];
		NSMenuItem *temperatureGraphItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
		temperatureGraphItem.view = temperatureGraphView;
		
		temperatureGraphView.dataSource = self.cpuTemperatures;
		temperatureGraphView.graphRange = NSMakeRange(0, 100);
		temperatureGraphView.fillGraph = NO;
		temperatureGraphView.isTemplate = self.isYosemite;
		temperatureGraphView.graphColor = self.isYosemite ? [NSColor whiteColor] : [NSColor blackColor];
		
		MenuGraphView *driveGraphView = [[MenuGraphView alloc] initWithFrame:CGRectMake(0, 0, 300, 70)];
		NSMenuItem *driveGraphItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
		driveGraphItem.view = driveGraphView;
		
		driveGraphView.dataSource = self.driveActivities;
		driveGraphView.graphRange = NSMakeRange(0, 50 * 1024 * 1024);	// 50MB
		driveGraphView.fillGraph = YES;
		driveGraphView.isTemplate = self.isYosemite;
		driveGraphView.graphColor = self.isYosemite ? [NSColor whiteColor] : [NSColor blackColor];

		NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
		NSString *quitTitle = [NSString stringWithFormat:@"Quit %@", appName];
		NSString *aboutTitle = [NSString stringWithFormat:@"About %@…", appName];
		
		NSMenu *diskMenu = [[NSMenu alloc] initWithTitle:@"Menu"];
		[diskMenu addItemWithTitle:aboutTitle action:@selector(about) keyEquivalent:@""];
		[diskMenu addItem:driveGraphItem];
		[diskMenu addItemWithTitle:quitTitle action:@selector(quit) keyEquivalent:@""];

		NSMenu *cpuMenu = [[NSMenu alloc] initWithTitle:@"Menu"];
		[cpuMenu addItemWithTitle:aboutTitle action:@selector(about) keyEquivalent:@""];
		[cpuMenu addItem:cpuGraphItem];
		[cpuMenu addItemWithTitle:quitTitle action:@selector(quit) keyEquivalent:@""];

		NSMenu *temperatureMenu = [[NSMenu alloc] initWithTitle:@"Menu"];
		[temperatureMenu addItemWithTitle:aboutTitle action:@selector(about) keyEquivalent:@""];
		[temperatureMenu addItem:temperatureGraphItem];
		[temperatureMenu addItemWithTitle:quitTitle action:@selector(quit) keyEquivalent:@""];
		
		[self.diskStatusItem setMenu:diskMenu];
		[self.cpuStatusItem setMenu:cpuMenu];
		[self.cpuTemperatureStatusItem setMenu:temperatureMenu];
	}
}

- (void)drawCPUActivity
{
	[self.cpuStatusImage lockFocus];
	
	[[NSColor clearColor] set];
	NSSize imageSize = self.cpuStatusImage.size;
	
	NSRectFill(NSMakeRect(0,0, imageSize.width, imageSize.height));
    
	NSString *cpuString = [NSString stringWithFormat:@"%ld%%", self.cpuActivity];
		
	if ([cpuString length] > 3)
	{
		if (!self.isYosemite)
			[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 4, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes3DigitsAlpha];
		
		[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 5, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes3Digits];
	}
	else
	{
		if (!self.isYosemite)
			[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 5, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes2DigitsAlpha];
		
		[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 6, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes2Digits];
	}
	
	[self.cpuStatusImage unlockFocus];
	[self.cpuStatusItem setImage:self.cpuStatusImage];
}

- (void)drawDriveActivity
{
	[self.diskStatusImage lockFocus];
	
	[[NSColor clearColor] set];
	NSSize imageSize = self.diskStatusImage.size;
	
	NSRectFill(NSMakeRect(0,0, imageSize.width, imageSize.height));
	
	NSBezierPath *path = nil;
	NSPoint center = NSMakePoint(imageSize.width / 2.0f, imageSize.height / 2.0f);
	center.y -= 0.5;
	float radius = 0.65f * (imageSize.width / 2.0f);
	
	// Draw a full white and black circle...
	if (!self.isYosemite)
	{
		path = [NSBezierPath bezierPath];
		[path appendBezierPathWithArcWithCenter:NSMakePoint(center.x, center.y - 1.0f)
										 radius:radius
									 startAngle:0
									   endAngle:360
									  clockwise:NO];
		
		[[NSColor colorWithCalibratedWhite:1.0f alpha:0.5f] set];
		[path setLineWidth:2];
		[path stroke];
	}
	
	path = [NSBezierPath bezierPath];
	[path appendBezierPathWithArcWithCenter:center
									 radius:radius
								 startAngle:0
								   endAngle:360
								  clockwise:NO];
	
	[[NSColor blackColor] set];
	[path setLineWidth:self.isYosemite ? 1 : 2];
	[path stroke];
	
	if (self.driveActivity != 0)
	{
		float smallRadius = 0.45f * (imageSize.width / 2.0f);

		path = [NSBezierPath bezierPath];
		[path appendBezierPathWithArcWithCenter:center
										 radius:smallRadius
									 startAngle:0
									   endAngle:360
									  clockwise:NO];
		
		[[NSColor blackColor] set];
		[path fill];
	}

	if ((self.driveActivity & DRIVE_WRITE) != 0)
	{
		float smallRadius = 0.35f * (imageSize.width / 2.0f);
		
		path = [NSBezierPath bezierPath];
		[path appendBezierPathWithArcWithCenter:center
										 radius:smallRadius
									 startAngle:0
									   endAngle:360
									  clockwise:NO];
		
		[[NSColor whiteColor] set];
		[path fill];
	}
	
	[self.diskStatusImage unlockFocus];
	[self.diskStatusItem setImage:self.diskStatusImage];
}

- (void)drawCPUTemperature
{
	[self.cpuTemperatureStatusImage lockFocus];
	
	[[NSColor clearColor] set];
	NSSize imageSize = self.cpuTemperatureStatusImage.size;
	
	NSRectFill(NSMakeRect(0,0, imageSize.width, imageSize.height));
	
	NSInteger temperature = self.cpuTemperature;
	if (!self.isMetric)
	{
		double temp = temperature;
		temp *= 1.80;
		temp += 32.0;
		temperature = temp;
	}
	
	NSString *cpuString = [NSString stringWithFormat:@"%ld°", temperature];
	
	if ([cpuString length] > 4)
	{
		if (!self.isYosemite)
			[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 4, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes3DigitsAlpha];
		
		[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 5, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes3Digits];
	}
	else
	{
		if (!self.isYosemite)
			[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 5, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes2DigitsAlpha];
		
		[cpuString drawInRect:NSMakeRect(0, -imageSize.height / 2 + 6, imageSize.width, imageSize.height) withAttributes:self.cpuAttributes2Digits];
	}
	
	[self.cpuTemperatureStatusImage unlockFocus];
	[self.cpuTemperatureStatusItem setImage:self.cpuTemperatureStatusImage];
}

#pragma mark CPU information

- (void)setupCPUActivity
{
	int mib[2U] = { CTL_HW, HW_NCPU };
    size_t sizeOfNumCPUs = sizeof(numCPUs);
    
	int status = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    
	if(status) numCPUs = 1;
	
	// Attributes for drawing
	NSMutableParagraphStyle *paragrapStyle = [[NSMutableParagraphStyle alloc] init];
	paragrapStyle.alignment = NSCenterTextAlignment;
		
	self.cpuAttributes3Digits = @{ NSFontAttributeName: [NSFont systemFontOfSize:8], NSParagraphStyleAttributeName: paragrapStyle };
	self.cpuAttributes2Digits = @{ NSFontAttributeName: [NSFont systemFontOfSize:11], NSParagraphStyleAttributeName: paragrapStyle };

	self.cpuAttributes3DigitsAlpha = @{ NSFontAttributeName: [NSFont systemFontOfSize:8], NSParagraphStyleAttributeName: paragrapStyle, NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1.0 alpha:0.5] };
	self.cpuAttributes2DigitsAlpha = @{ NSFontAttributeName: [NSFont systemFontOfSize:11], NSParagraphStyleAttributeName: paragrapStyle, NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1.0 alpha:0.5] };
}

- (void)updateCPU:(NSTimer *)timer
{
	natural_t numCPUsU = 0U;
	kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);
	
	float totalInUse = 0.0f;
	float totalMax = 0.0f;
	
	if (err == KERN_SUCCESS)
	{
		for(unsigned i = 0U; i < numCPUs; ++i)
		{
			float inUse, total;
			
			if(prevCpuInfo)
			{
				inUse = (
						 (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER])
						 + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM])
						 + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE])
						 );
				
				total = inUse + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE]);
			}
			else
			{
				inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
				total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
			}
			
			totalInUse += inUse;
			totalMax += total;
		}
		
		if (prevCpuInfo)
		{
			size_t prevCpuInfoSize = sizeof(integer_t) * numPrevCpuInfo;
			vm_deallocate(mach_task_self(), (vm_address_t)prevCpuInfo, prevCpuInfoSize);
		}
		
		prevCpuInfo = cpuInfo;
		numPrevCpuInfo = numCpuInfo;
		
		cpuInfo = NULL;
		numCpuInfo = 0U;
		
		NSInteger cpuActivity = (NSInteger)((totalInUse / totalMax) * 100.0);

		if (cpuActivity != self.cpuActivity) self.cpuActivity = cpuActivity;
		
		[self.cpuActivities addObject:[NSNumber numberWithInteger:cpuActivity]];
		if ([self.cpuActivities count] > 300) [self.cpuActivities removeObjectAtIndex:0];
	}
}

#pragma mark Block device change notifications and IOKit interaction.

static void BlockDeviceChanged(void *ref, io_iterator_t iterator)
{
	if (ref) [(__bridge AppDelegate *)ref blockDeviceChanged:iterator];
}

- (void)setupBlockDeviceNotifications
{
	// Connect to IOKit and setup our notification source
	kern_return_t err = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if ((err != KERN_SUCCESS) || !masterPort) return;
	
	notifyPort = IONotificationPortCreate(masterPort);
	if (!notifyPort) return;
	
	notifyRunSource = IONotificationPortGetRunLoopSource(notifyPort);
	if (!notifyRunSource) return;
	
	CFRunLoopAddSource(CFRunLoopGetCurrent(), notifyRunSource, kCFRunLoopDefaultMode);
	
	// Install notifications for block storage devices
	err = IOServiceAddMatchingNotification(notifyPort,  kIOPublishNotification,
										   IOServiceMatching(kIOBlockStorageDriverClass),
										   BlockDeviceChanged, (__bridge void *)(self), &blockDevicePublishedIterator);
	if (err != KERN_SUCCESS) return;
	
	err = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification,
										   IOServiceMatching(kIOBlockStorageDriverClass),
										   BlockDeviceChanged, (__bridge void *)(self), &blockDeviceTerminatedIterator);
	if (err != KERN_SUCCESS) return;
	
	// Pump both iterators
	BlockDeviceChanged((__bridge void *)(self), blockDevicePublishedIterator);
	BlockDeviceChanged((__bridge void *)(self), blockDeviceTerminatedIterator);
}

- (void)blockDeviceChanged:(io_iterator_t)iterator
{
	// Remove the current drive iterator, forcing its recreation later
	if (blockDeviceIterator) IOObjectRelease(blockDeviceIterator);
	blockDeviceIterator = MACH_PORT_NULL;
	
	// Drain the iterator
	io_service_t someDevice = IOIteratorNext(iterator);
	while (someDevice)
	{
		IOObjectRelease(someDevice);
		someDevice = IOIteratorNext(iterator);
	}
}

- (void)updateIO:(NSTimer *)timer
{
	NSInteger driveActivity = 0;
	
	// Check that the iterator is still good, if not get a new one
	if (!blockDeviceIterator)
	{
		kern_return_t err = IOServiceGetMatchingServices(masterPort,
														 IOServiceMatching(kIOBlockStorageDriverClass),
														 &blockDeviceIterator);
		if (err != KERN_SUCCESS) return;
	}
	
	// Iterate the device list from IOKit and figure out if we're reading
	// or writing
	io_registry_entry_t driveEntry = MACH_PORT_NULL;
	UInt64 totalRead = 0, totalWrite = 0;
	
	while ((driveEntry = IOIteratorNext(blockDeviceIterator)))
	{
 		// Get the statistics for this drive
		CFDictionaryRef statistics = IORegistryEntryCreateCFProperty(driveEntry,
																	 CFSTR(kIOBlockStorageDriverStatisticsKey),
																	 kCFAllocatorDefault,
																	 kNilOptions);
		
		// If we got the statistics block for this device then we can add it to our totals
		if (statistics)
		{
			// Get total bytes read
			NSNumber *statNumber = (NSNumber *)[(__bridge NSDictionary *)statistics objectForKey:
												(NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey)];
			if (statNumber)
			{
				totalRead += [statNumber unsignedLongLongValue];
			}
			
			// Bytes written
			statNumber = (NSNumber *)[(__bridge NSDictionary *)statistics objectForKey:
									  (NSString *)CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey)];
			if (statNumber)
			{
				totalWrite += [statNumber unsignedLongLongValue];
			}
			
			// Release
			CFRelease(statistics);
		}

		if (driveEntry)
		{
			IOObjectRelease(driveEntry);
		}
	}
	
	// Reset our drive list
	IOIteratorReset(blockDeviceIterator);
	
	// Once we have totals all we care is if they changed. Calculating actual
	// delta isn't important, since unmounts and overflows will change the
	// values. We're basically assuming that unmount == read/write, but
	// close enough.
	if (totalRead != previousTotalRead) driveActivity |= DRIVE_READ;
	if (totalWrite != previousTotalWrite) driveActivity |= DRIVE_WRITE;
	
	previousTotalRead = totalRead;
	previousTotalWrite = totalWrite;

	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	
	if (previousTotalRead3Seconds == 0)
	{
		previousTotalRead3Seconds = totalRead;
		previousTotalWrite3Seconds = totalWrite;
		absoluteTime3Seconds = now;
	}
	
	if (now - absoluteTime3Seconds >= 3.0)
	{
		// 3 seconds passed.
		UInt64 deltaRead = totalRead - previousTotalRead3Seconds;
		UInt64 deltaWrite = totalWrite - previousTotalWrite3Seconds;
		
		if (previousTotalRead3Seconds > totalRead) deltaRead = 0;
		if (previousTotalWrite3Seconds > totalWrite) deltaWrite = 0;
		
		UInt64 delta = deltaRead + deltaWrite;
		
		NSNumber *num = [NSNumber numberWithLongLong:delta];
		[self.driveActivities addObject:num];
		if ([self.driveActivities count] > 300) [self.driveActivities removeObjectAtIndex:0];
		
		previousTotalRead3Seconds = totalRead;
		previousTotalWrite3Seconds = totalWrite;
		absoluteTime3Seconds = now;
	}
	
	
	if (driveActivity != self.driveActivity)
	{
		self.driveActivity = driveActivity;
		
		if (driveActivity != 0)
		{
			[self.diskTimer invalidate];
			self.diskTimer = [NSTimer timerWithTimeInterval:FAST_TIMER target:self selector:@selector(updateIO:) userInfo:nil repeats:YES];
			[[NSRunLoop mainRunLoop] addTimer:self.diskTimer forMode:NSRunLoopCommonModes];
		}
		else
		{
			[self.diskTimer invalidate];
			self.diskTimer = [NSTimer timerWithTimeInterval:SLOW_TIMER target:self selector:@selector(updateIO:) userInfo:nil repeats:YES];
			[[NSRunLoop mainRunLoop] addTimer:self.diskTimer forMode:NSRunLoopCommonModes];
		}
	}
}

#pragma mark Temperature monitoring

- (void)setupTemperature
{
	sensors = [[SMCSensors alloc] init];
	
	NSDictionary *keys = [sensors allValues];
	
	NSString *formatString = @"NULL";
	enableCPUMonitoring = NO;
	
	NSUInteger offset = 0;
	
	if (keys[@"TC0D"]) { enableCPUMonitoring = YES; formatString = @"TC%dD"; }
	if (keys[@"TC0C"]) { enableCPUMonitoring = YES; formatString = @"TC%dC"; }
	if (keys[@"TC1C"] && !enableCPUMonitoring) { enableCPUMonitoring = YES; formatString = @"TC%dC"; offset = 1; }
	
	NSMutableArray *k = [NSMutableArray array];
	for (NSUInteger i = 0; i < numCPUs; i++)
	{
		NSString *cpu = [NSString stringWithFormat:formatString, i + offset];
		if (keys[cpu]) [k addObject:cpu];
	}
	
	cpuKeys = [NSArray arrayWithArray:k];

	if (!enableCPUMonitoring)
	{
		[[NSStatusBar systemStatusBar] removeStatusItem:self.cpuTemperatureStatusItem];
		self.cpuTemperatureStatusItem = nil;
	}
}

- (void)updateTemperature:(NSTimer *)timer
{
	NSDictionary *keys = [sensors temperatureValuesExtended:YES];
	
	__block NSInteger maxTemp = 0;
	
	[cpuKeys enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
		NSNumber *value = keys[obj];
		if ([value integerValue] > maxTemp) maxTemp = [value integerValue];
	}];
	
	if (maxTemp != self.cpuTemperature) self.cpuTemperature = maxTemp;
	
	[self.cpuTemperatures addObject:[NSNumber numberWithInteger:maxTemp]];
	if ([self.cpuTemperatures count] > 300) [self.cpuTemperatures removeObjectAtIndex:0];
}

@end
