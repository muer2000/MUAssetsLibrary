//
//  MUAssetsViewController.h
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/13.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MUAssetsLibrary, MUAssetCollection;

@interface MUAssetsViewController : UICollectionViewController

@property (nonatomic, weak) MUAssetsLibrary *assetsLibrary;
@property (nonatomic, weak) MUAssetCollection *assetCollection;

@end
