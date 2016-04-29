//
//  MUAssetsViewController.m
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/13.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import "MUAssetsViewController.h"
#import "MUAssetsLibrary.h"
#import "MUAssetCell.h"
#import "MUAssetImageManager.h"

static const NSUInteger kColumnNum = 4;

#define kIsiOS8 (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1)

@interface MUAssetsViewController ()

@property (nonatomic, assign) CGRect previousPreheatRect;
@property (nonatomic, strong) NSDictionary *metadataInfo;

@end

@implementation MUAssetsViewController

static NSString * const reuseIdentifier = @"AssetCell";

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.assetCollection.title;
    [self resetCachedAssets];
}

- (MUAsset *)assetForIndexPath:(NSIndexPath *)indexPath
{
    return self.assetCollection.fetchResult[indexPath.item];
}

   
#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.assetCollection.fetchResult.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    MUAsset *asset = [self assetForIndexPath:indexPath];
    MUAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    NSInteger tag = indexPath.item;
    cell.tag = tag;
    [MUAssetImageManager requestThumbnailForAsset:asset resultHandler:^(UIImage *image, NSDictionary *info) {
        if (cell.tag == tag) {
            if (cell.imageView.image != image) {
                cell.imageView.image = image;
            }
        }
    }];
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)collectionView.collectionViewLayout;
    CGFloat spacing = layout.minimumInteritemSpacing;
    CGFloat side = (CGRectGetWidth(self.view.bounds) - spacing * (kColumnNum - 1)) / kColumnNum;
    return CGSizeMake(side, side);
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateCachedAssets];
}


#pragma mark - iOS8 Asset Caching

- (void)resetCachedAssets
{
    if (kIsiOS8) {
        return;
    }
    [MUAssetImageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets
{
    if (!kIsiOS8) {
        return;
    }
    BOOL isViewVisible = [self isViewLoaded] && [[self view] window] != nil;
    if (!isViewVisible) { return; }
    
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0f, -0.5f * CGRectGetHeight(preheatRect));
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0f) {
        
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        } addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        }];
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        [MUAssetImageManager startCachingThumbnailForAssets:assetsToStartCaching];
        [MUAssetImageManager stopCachingThumbnailForAssets:assetsToStopCaching];
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect removedHandler:(void (^)(CGRect removedRect))removedHandler addedHandler:(void (^)(CGRect addedRect))addedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)indexPathsForElementsInRect:(CGRect)rect
{
    NSArray *allLayoutAttributes = [self.collectionView.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths
{
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *resultAssets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *itemIndexPath in indexPaths) {
        MUAsset *asset = [self assetForIndexPath:itemIndexPath];
        [resultAssets addObject:asset];
    }
    return resultAssets;
}


@end
