//
//  UIImage+DrawBlock.h
//  onedcamera
//
//  Created by Emiel Lensink on 12-7-13.
//  Copyright (c) 2013 Emiel Lensink. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSImage (DrawBlock)

+ (NSImage *)imageWithSize:(CGSize)size opaque:(BOOL)opaque drawBlock:(void(^)(CGContextRef ctx, CGSize size))drawBlock;

+ (NSImage *)imageWithSize:(CGSize)size opaque:(BOOL)opaque scale:(float)scale drawBlock:(void(^)(CGContextRef ctx, CGSize size))drawBlock;

@end
