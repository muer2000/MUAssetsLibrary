//
//  MUAssetCollection.m
//  MUAssetsLibrary
//
//  Created by Muer on 15/9/24.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import "MUAssetCollection.h"
#import <Photos/Photos.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "MUAsset.h"

static const CGSize kPosterImageSize = {150.0, 150.0};

@interface MUAssetFetchResult (MUPrivate)

+ (instancetype)p_fetchResultWithAssetInPHFetchResult:(PHFetchResult<PHAsset *> *)phFetchResult;
+ (instancetype)p_fetchResultWithPHAssets:(NSArray<PHAsset *> *)phAssets;
+ (instancetype)p_fetchResultWithAssetsGroup:(ALAssetsGroup *)assetsGroup;

@end

@interface MUAssetCollection ()

- (void)p_reloadAssetCollection;

@property (nonatomic, strong) id realAssetCollection;

@property (nonatomic, copy) NSString *localIdentifier;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIImage *posterImage;

@property (nonatomic, assign) MUAssetCollectionType type;
@property (nonatomic, assign) MUAssetCollectionSubtype subType;
@property (nonatomic, assign) NSInteger numberOfAssets;
@property (nonatomic, strong) MUAssetFetchResult *fetchResult;

@property (nonatomic, assign) NSInteger sortIndex;

// >= 8.1
@property (nonatomic, strong) PHFetchResult<PHAsset *> *phFetchResult;
// 8.0~8.1
@property (nonatomic, strong) NSArray<PHAsset *> *allPhotoAssets;

@end

@implementation MUAssetCollection

- (int32_t)requestPosterImageWithCompletionHandler:(void(^)(UIImage *image, NSDictionary *info))completionHandler
{
    if (!completionHandler) {
        return 0;
    }
    if (_posterImage) {
        completionHandler(_posterImage, nil);
        return 0;
    }
    PHAsset *posterAsset = nil;
    if (self.phFetchResult) {
        // 系统相册取最新的
        if (self.subType < MUAssetCollectionSubtypeAlbumMyPhotoStream) {
            posterAsset = self.phFetchResult.firstObject;
        }
        else {
            posterAsset = self.phFetchResult.lastObject;
        }
    }
    else if (self.allPhotoAssets) {
        posterAsset = self.allPhotoAssets.lastObject;
    }
    if (!posterAsset) {
        completionHandler(nil, nil);
        return 0;
    }
    return [[PHImageManager defaultManager] requestImageForAsset:posterAsset
                                                      targetSize:kPosterImageSize
                                                     contentMode:PHImageContentModeAspectFill
                                                         options:nil
                                                   resultHandler:^(UIImage *result, NSDictionary *info) {
                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                           _posterImage = result;
                                                           completionHandler(result, info);
                                                       });
                                                   }];
}

- (BOOL)addAsset:(MUAsset *)asset
{
    if ([self.realAssetCollection isKindOfClass:[PHAssetCollection class]]) {
        NSError *error = nil;
        [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
            PHAssetCollectionChangeRequest *changeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:self.realAssetCollection];
            [changeRequest addAssets:@[asset.realAsset]];
        } error:&error];
        return (error == nil);
    }
    
    ALAssetsGroup *group = self.realAssetCollection;
    return [group addAsset:asset.realAsset];
}

- (NSString *)description
{
    return self.localIdentifier;
}

- (MUAssetFetchResult *)fetchResult
{
    if (!_fetchResult) {
        if (_phFetchResult) {
            _fetchResult = [MUAssetFetchResult p_fetchResultWithAssetInPHFetchResult:_phFetchResult];
        }
        else if ([_realAssetCollection isKindOfClass:[ALAssetsGroup class]]) {
            _fetchResult = [MUAssetFetchResult p_fetchResultWithAssetsGroup:_realAssetCollection];
        }
        else if (_allPhotoAssets) {
            _fetchResult = [MUAssetFetchResult p_fetchResultWithPHAssets:_allPhotoAssets];
        }
    }
    return _fetchResult;
}


#pragma mark - Private

static NSArray *MUAssetCollectionSubTypeIndexs() {
    static NSArray *indexs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        indexs = @[@(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
                   @(PHAssetCollectionSubtypeAlbumMyPhotoStream),
                   @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded),
                   @(PHAssetCollectionSubtypeSmartAlbumFavorites)];
    });
    return indexs;
}

- (void)p_reloadAssetCollection
{
    if ([self.realAssetCollection isKindOfClass:[ALAssetsGroup class]]) {
        ALAssetsGroup *group = self.realAssetCollection;
        self.url = [group valueForProperty:ALAssetsGroupPropertyURL];
        self.localIdentifier = self.url.absoluteString;
        self.title = [group valueForProperty:ALAssetsGroupPropertyName];
        self.posterImage = [UIImage imageWithCGImage:group.posterImage];
        self.type = MUAssetCollectionTypeAlbum;
        self.subType = MUAssetCollectionSubtypeAlbumRegular;
        self.numberOfAssets = group.numberOfAssets;
    }
    else {
        self.localIdentifier = [self.realAssetCollection localIdentifier];
        self.url = [self p_urlWithLocalIdentifier:self.localIdentifier];
        self.title = [self.realAssetCollection localizedTitle];
        self.type = (MUAssetCollectionType)[self.realAssetCollection assetCollectionType];
        // is all photo or camera roll
        if (self.allPhotoAssets) {
            self.subType = MUAssetCollectionSubtypeSmartAlbumUserLibrary;
            self.numberOfAssets = self.allPhotoAssets.count;
        }
        else {
            self.subType = (MUAssetCollectionSubtype)[self.realAssetCollection assetCollectionSubtype];
            self.numberOfAssets = self.phFetchResult.count;
        }
        // sort by index
        self.sortIndex = [MUAssetCollectionSubTypeIndexs() indexOfObject:@(self.subType)];
    }
}

- (NSURL *)p_urlWithLocalIdentifier:(NSString *)localIdentifier
{
    if (localIdentifier.length > 0) {
        return [NSURL URLWithString:[NSString stringWithFormat:@"%@://group/%@", PHAssetURLScheme, localIdentifier]];
    }
    return nil;
}

@end


@interface MUAssetCollection (MUPrivate)

+ (instancetype)p_assetCollectionWithAssetsGroup:(ALAssetsGroup *)group;
+ (instancetype)p_assetCollectionWithPHAssetCollection:(PHAssetCollection *)phAssetCollection fetchOptions:(PHFetchOptions *)fetchOptions;
+ (instancetype)p_allPhotosCollectionWithTitle:(NSString *)title fetchOptions:(PHFetchOptions *)fetchOptions;

@property (nonatomic, readonly) NSInteger sortIndex;

@end

@implementation MUAssetCollection (MUPrivate)

+ (instancetype)p_assetCollectionWithAssetsGroup:(ALAssetsGroup *)group
{
    MUAssetCollection *assetCollection = [[MUAssetCollection alloc] init];
    assetCollection.realAssetCollection = group;
    [assetCollection p_reloadAssetCollection];
    return assetCollection;
}

+ (instancetype)p_assetCollectionWithPHAssetCollection:(PHAssetCollection *)phAssetCollection fetchOptions:(PHFetchOptions *)fetchOptions
{
    MUAssetCollection *assetCollection = [[MUAssetCollection alloc] init];
    assetCollection.realAssetCollection = phAssetCollection;
    assetCollection.phFetchResult = [PHAsset fetchAssetsInAssetCollection:phAssetCollection options:fetchOptions];
    [assetCollection p_reloadAssetCollection];
    return assetCollection;
}

+ (instancetype)p_allPhotosCollectionWithTitle:(NSString *)title fetchOptions:(PHFetchOptions *)fetchOptions
{
    /* 8.1前fetchAssetsWithOptions会返回已删除的资源,故需要加谓词过滤assetSource=3的数据,
     assetSource等同于iOS9的PHAssetSourceType
     另一种方法用fetchMomentsWithOptions遍历PHAssetCollection得到所有资源,但相对速度较慢
     */
    MUAssetCollection *assetCollection = [[MUAssetCollection alloc] init];
    PHFetchResult *assetsFR = [PHAsset fetchAssetsWithOptions:fetchOptions];
    if (assetsFR.count > 0) {
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, assetsFR.count)];
        NSMutableArray *assetArray = [NSMutableArray arrayWithArray:[assetsFR objectsAtIndexes:indexSet]];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"description contains %@", @"assetSource=3"];
        [assetArray filterUsingPredicate:predicate];
        
        assetCollection.allPhotoAssets = assetArray;
        assetCollection.realAssetCollection = [PHAssetCollection transientAssetCollectionWithAssets:assetArray title:title];
    }
    [assetCollection p_reloadAssetCollection];
    return assetCollection;
}

@end
