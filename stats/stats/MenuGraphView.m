//
//  MenuGraphView.m
//  stats
//
//  Created by Emiel Lensink on 26/10/14.
//  Copyright (c) 2014 Emiel Lensink. All rights reserved.
//

#import "MenuGraphView.h"

#import "NSImage+DrawBlock.h"

@interface MenuGraphView ()
{
	
}

@property (nonatomic, strong) NSTimer *drawTimer;
@property (nonatomic, strong) NSImageView *imageView;

@end

@implementation MenuGraphView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self)
	{
		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
	
		self.graphColor = [NSColor whiteColor];
		
		self.imageView = imageView;
		[self addSubview:imageView];
	}
	return self;
}


- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
}

- (void)updateImageView
{
	CGRect frame = self.frame;
	CGSize size = frame.size;
	
	NSImage *image = [NSImage imageWithSize:size opaque:YES drawBlock:^(CGContextRef ctx, CGSize size)
					  {
						  if ([self.dataSource count] >= 2)
						  {
							  NSBezierPath *path = [NSBezierPath bezierPath];
							  
							  CGFloat scale = (size.height - 4.5) / (double)self.graphRange.length;
							  
							  NSInteger offset = 300;
							  for (NSNumber *obj in [self.dataSource reverseObjectEnumerator])
							  {
								  CGFloat x = offset + 0.5;
								  CGFloat y = ([obj doubleValue] - (double)self.graphRange.location);
								  if (y < 0) y = 0;
								  y *= scale;
								  y += 2.5;
								  
								  if (y > (size.height - 4.5)) y = (size.height - 4.5);
								  
								  if (offset == 300)
									  [path moveToPoint:NSMakePoint(x, y)];
								  else
									  [path lineToPoint:NSMakePoint(x, y)];
								  
								  offset -= 1;
							  }
							  
							  offset += 1;

							  if (self.fillGraph)
							  {
								  [path lineToPoint:NSMakePoint(offset, 2)];
								  [path lineToPoint:NSMakePoint(300, 2)];
								  
								  [self.graphColor setFill];
								  [path fill];
							  }
							  else
							  {
								  [path setLineWidth:2];
								  [self.graphColor set];
								  [path stroke];
							  }
						  }
						  
						  [self.graphColor set];
						  NSBezierPath *line = [NSBezierPath bezierPathWithRect:NSMakeRect(-5.5, 0.5, 310, size.height - 1)];
						  [line stroke];
					  }];
	
	if (self.isTemplate) [image setTemplate:YES];
	
	self.imageView.image = image;
}

- (void)viewDidMoveToWindow
{
	if (self.window)
	{
		if (self.drawTimer) [self.drawTimer invalidate];
		self.drawTimer = [NSTimer timerWithTimeInterval:3 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
		[[NSRunLoop mainRunLoop] addTimer:self.drawTimer forMode:NSRunLoopCommonModes];
		
		[self updateImageView];
	}
	else
	{
		[self.drawTimer invalidate];
		self.drawTimer = nil;
	}
}

- (void)timerFired:(NSTimer *)sender
{
	//[self setNeedsDisplay:YES];
	[self updateImageView];
}

@end
