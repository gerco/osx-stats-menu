//
//  UIImage+DrawBlock.m
//  onedcamera
//
//  Created by Emiel Lensink on 12-7-13.
//  Copyright (c) 2013 Emiel Lensink. All rights reserved.
//

#import "NSImage+DrawBlock.h"

@implementation NSImage (DrawBlock)

+ (NSImage *)imageWithSize:(CGSize)size opaque:(BOOL)opaque drawBlock:(void(^)(CGContextRef ctx, CGSize size))drawBlock
{
	return [NSImage imageWithSize:size opaque:opaque scale:0 drawBlock:drawBlock];
}

+ (NSImage *)imageWithSize:(CGSize)size opaque:(BOOL)opaque scale:(float)scale drawBlock:(void(^)(CGContextRef ctx, CGSize size))drawBlock
{
	NSImage *image = [[NSImage alloc] initWithSize:size];
	[image lockFocusFlipped:NO];
	
	CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
	
	drawBlock(ctx, size);

	[image unlockFocus];
	
	return image;
}


@end
