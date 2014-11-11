//
//  MenuGraphView.h
//  stats
//
//  Created by Emiel Lensink on 26/10/14.
//  Copyright (c) 2014 Emiel Lensink. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MenuGraphView : NSView

@property (nonatomic, assign) NSRange graphRange;
@property (nonatomic, strong) NSArray *dataSource;
@property (nonatomic, assign) BOOL fillGraph;

@property (nonatomic, assign) BOOL isTemplate;
@property (nonatomic, strong) NSColor *graphColor;

@end
