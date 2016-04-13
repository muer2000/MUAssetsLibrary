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
#import "MUAssetCollection.h"

@interface MUAsset ()

+ (instancetype)p_assetWithPHAsset:(PHAsset *)phAsset;
+ (instancetype)p_assetWithALAsset:(ALAsset *)alAsset;

@end


@interface MUAssetCollection ()

// >= 8.1
@property (nonatomic, strong) PHFetchResult<PHAsset *> *assetsFetchResult;
// 8.0~8.1
@property (nonatomic, strong) NSArray<PHAsset *> *assetsInAllPhoto;

@end


@interface MUAssetFetchResult ()

+ (MUAsset *)p_sharedNullAsset;
- (NSUInteger)p_numberOfAssets;
- (id)p_assetAtIndex:(NSUInteger)index;
- (void)p_preloadData;

@property (nonatomic, strong) NSMutableArray<MUAsset *> *assetArray;
@property (nonatomic, assign) NSUInteger numberOfPreload;

@property (nonatomic, weak) NSArray<PHAsset *> *phAssets;
@property (nonatomic, weak) PHFetchResult<PHAsset *> *phFetchResult;
@property (nonatomic, weak) ALAssetsGroup *assetsGroup;

@end

@implementation MUAssetFetchResult

+ (instancetype)resultWithAssetCollection:(MUAssetCollection *)assetCollection
{
    return [self resultWithAssetCollection:assetCollection numberOfPreload:100];
}

+ (instancetype)resultWithAssetCollection:(MUAssetCollection *)assetCollection numberOfPreload:(NSUInteger)numberOfPreload
{
    MUAssetFetchResult *frInstance = [[MUAssetFetchResult alloc] init];
    frInstance.numberOfPreload = numberOfPreload;
    if (assetCollection.assetsFetchResult) {
        frInstance.phFetchResult = assetCollection.assetsFetchResult;
    }
    else if (assetCollection.assetsInAllPhoto) {
        frInstance.phAssets = assetCollection.assetsInAllPhoto;
    }
    else if ([assetCollection.realAssetCollection isKindOfClass:[ALAssetsGroup class]]) {
        frInstance.assetsGroup = assetCollection.realAssetCollection;
    }
    [frInstance p_preloadData];
    return frInstance;
}

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
        NSRange range = NSMakeRange(0, MIN(self.numberOfPreload, numberOfAssets));
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];
        [self.assetsGroup enumerateAssetsAtIndexes:indexSet options:0 usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
            if (result) {
                [self.assetArray addObject:[MUAsset p_assetWithALAsset:result]];
            }
        }];
        NSInteger nullCount = MAX(0, numberOfAssets - self.numberOfPreload);
        for (int i = 0; i < nullCount; i++) {
            [self.assetArray addObject:[MUAssetFetchResult p_sharedNullAsset]];
        }
    }
    else {
        for (int i = 0; i < numberOfAssets; i++) {
            if (i < self.numberOfPreload) {
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
