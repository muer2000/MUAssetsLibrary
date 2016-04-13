//
//  MUAssetCell.m
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/13.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import "MUAssetCell.h"


@implementation MUAssetCell

- (void)prepareForReuse
{
    [super prepareForReuse];
    _imageView.image = nil;
}

@end
