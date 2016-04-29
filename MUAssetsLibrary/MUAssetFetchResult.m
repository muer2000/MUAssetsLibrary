//
//  MUAssetFetchResult.m
//  MUAssetsLibrary
//
//  Created by Muer on 15/9/25.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import "MUAssetFetchResult.h"
#import <Photos/Photos.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "MUAsset.h"

static const NSUInteger kNumberOfPreload = 100;

@interface MUAsset (MUPrivate)

+ (instancetype)p_assetWithPHAsset:(PHAsset *)phAsset;
+ (instancetype)p_assetWithALAsset:(ALAsset *)alAsset;

@end

@interface MUAssetFetchResult ()

+ (MUAsset *)p_sharedNullAsset;

- (NSUInteger)p_numberOfAssets;
- (id)p_assetAtIndex:(NSUInteger)index;
- (void)p_preloadData;

@property (nonatomic, strong) NSMutableArray<MUAsset *> *assetArray;

@property (nonatomic, weak) NSArray<PHAsset *> *phAssets;
@property (nonatomic, weak) PHFetchResult<PHAsset *> *phFetchResult;
@property (nonatomic, weak) ALAssetsGroup *assetsGroup;

@end

@implementation MUAssetFetchResult

- (BOOL)containsObject:(MUAsset *)anObject
{
    return [self.assetArray containsObject:anObject];
}

- (NSUInteger)indexOfObject:(MUAsset *)anObject
{
    return [self.assetArray indexOfObject:anObject];
}

- (MUAsset *)objectAtIndex:(NSUInteger)index
{
    if (index < self.count) {
        return [self p_assetAtIndex:index];
    }
    return nil;
}

- (MUAsset *)objectAtIndexedSubscript:(NSUInteger)idx
{
    if (idx < self.count) {
        [self p_assetAtIndex:idx];
        return [self.assetArray objectAtIndexedSubscript:idx];
    }
    return nil;
}

- (void)enumerateObjectsUsingBlock:(void (^)(MUAsset *obj, NSUInteger idx, BOOL *stop))block
{
    [self.assetArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id asset = [self p_assetAtIndex:idx];
        return block(asset, idx, stop);
    }];
}

- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(MUAsset *obj, NSUInteger idx, BOOL *stop))block
{
    [self.assetArray enumerateObjectsWithOptions:opts usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id asset = [self p_assetAtIndex:idx];
        return block(asset, idx, stop);
    }];
}

- (void)enumerateObjectsAtIndexes:(NSIndexSet *)s options:(NSEnumerationOptions)opts usingBlock:(void (^)(MUAsset *obj, NSUInteger idx, BOOL *stop))block
{
    [self.assetArray enumerateObjectsAtIndexes:s options:opts usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id asset = [self p_assetAtIndex:idx];
        return block(asset, idx, stop);
    }];
}

- (NSUInteger)count
{
    return self.assetArray.count;
}

- (MUAsset *)firstObject
{
    if (self.count == 0) {
        return nil;
    }
    return [self p_assetAtIndex:0];
}

- (MUAsset *)lastObject
{
    if (self.count == 0) {
        return nil;
    }
    return [self p_assetAtIndex:self.count - 1];
}


#pragma mark - Private

+ (MUAsset *)p_sharedNullAsset
{
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MUAsset alloc] init];
    });
    return instance;
}

- (NSUInteger)p_numberOfAssets
{
    if (self.phFetchResult) {
        return self.phFetchResult.count;
    }
    if (self.assetsGroup) {
        return self.assetsGroup.numberOfAssets;
    }
    return self.phAssets.count;
}

- (id)p_assetAtIndex:(NSUInteger)index
{
    if (index >= self.count) {
        return nil;
    }
    id asset = self.assetArray[index];
    if (asset != [MUAssetFetchResult p_sharedNullAsset]) {
        return asset;
    }
    
    __block id bAsset = nil;
    if (self.assetsGroup) {
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:index];
        [self.assetsGroup enumerateAssetsAtIndexes:indexSet options:0 usingBlock:^(ALAsset *result, NSUInteger subIndex, BOOL *stop) {
            if (result) {
                bAsset = [MUAsset p_assetWithALAsset:result];
            }
            *stop = YES;
        }];
    }
    else {
        if (self.phFetchResult) {
            bAsset = [MUAsset p_assetWithPHAsset:self.phFetchResult[index]];
        }
        else {
            bAsset = [MUAsset p_assetWithPHAsset:self.phAssets[index]];
        }
    }
    if (bAsset) {
        [self.assetArray replaceObjectAtIndex:index withObject:bAsset];
    }
    return bAsset;
}

- (void)p_preloadData
{
    if (self.assetArray == nil) {
        self.assetArray = [NSMutableArray array];
    }
    [self.assetArray removeAllObjects];

    NSUInteger numberOfAssets = [self p_numberOfAssets];
    
    if (self.assetsGroup) {
        NSRange range = NSMakeRange(0, MIN(kNumberOfPreload, numberOfAssets));
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];
        [self.assetsGroup enumerateAssetsAtIndexes:indexSet options:0 usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
            if (result) {
                [self.assetArray addObject:[MUAsset p_assetWithALAsset:result]];
            }
        }];
        NSInteger nullCount = MAX(0, numberOfAssets - kNumberOfPreload);
        for (int i = 0; i < nullCount; i++) {
            [self.assetArray addObject:[MUAssetFetchResult p_sharedNullAsset]];
        }
    }
    else {
        for (int i = 0; i < numberOfAssets; i++) {
            if (i < kNumberOfPreload) {
                PHAsset *asset = self.phFetchResult ? self.phFetchResult[i] : self.phAssets[i];
                [self.assetArray addObject:[MUAsset p_assetWithPHAsset:asset]];
            }
            else {
                [self.assetArray addObject:[MUAssetFetchResult p_sharedNullAsset]];
            }
        }
    }
}

@end

@interface MUAssetFetchResult (MUPrivate)

+ (instancetype)p_fetchResultWithAssetInPHFetchResult:(PHFetchResult<PHAsset *> *)phFetchResult;
+ (instancetype)p_fetchResultWithPHAssets:(NSArray<PHAsset *> *)phAssets;
+ (instancetype)p_fetchResultWithAssetsGroup:(ALAssetsGroup *)assetsGroup;

@end

@implementation MUAssetFetchResult (MUPrivate)

+ (instancetype)p_fetchResultWithAssetInPHFetchResult:(PHFetchResult<PHAsset *> *)phFetchResult
{
    MUAssetFetchResult *instance = [[MUAssetFetchResult alloc] init];
    instance.phFetchResult = phFetchResult;
    [instance p_preloadData];
    return instance;
}

+ (instancetype)p_fetchResultWithPHAssets:(NSArray<PHAsset *> *)phAssets
{
    MUAssetFetchResult *instance = [[MUAssetFetchResult alloc] init];
    instance.phAssets = phAssets;
    [instance p_preloadData];
    return instance;
}

+ (instancetype)p_fetchResultWithAssetsGroup:(ALAssetsGroup *)assetsGroup
{
    MUAssetFetchResult *instance = [[MUAssetFetchResult alloc] init];
    instance.assetsGroup = assetsGroup;
    [instance p_preloadData];
    return instance;
}

@end