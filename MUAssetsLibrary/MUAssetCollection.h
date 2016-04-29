//
//  MUAssetCollection.h
//  MUAssetsLibrary
//
//  Created by Muer on 15/9/24.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MUAssetFetchResult.h"

/** 资源集类型 */
typedef NS_ENUM(NSInteger, MUAssetCollectionType) {
    MUAssetCollectionTypeAlbum      = 1,    // PHAssetCollectionTypeAlbum
    MUAssetCollectionTypeSmartAlbum = 2,    // PHAssetCollectionTypeSmartAlbum
    MUAssetCollectionTypeMoment     = 3,    // PHAssetCollectionTypeMoment
};

/** 资源集子类型 */
typedef NS_ENUM(NSInteger, MUAssetCollectionSubtype) {
    MUAssetCollectionSubtypeAlbumRegular            = 2,            // PHAssetCollectionSubtypeAlbumRegular
    MUAssetCollectionSubtypeAlbumMyPhotoStream      = 100,          // PHAssetCollectionSubtypeAlbumMyPhotoStream
    MUAssetCollectionSubtypeAlbumCloudShared        = 101,          // PHAssetCollectionSubtypeAlbumCloudShared
    MUAssetCollectionSubtypeSmartAlbumVideos        = 202,          // PHAssetCollectionSubtypeSmartAlbumVideos
    MUAssetCollectionSubtypeSmartAlbumUserLibrary   = 209,          // PHAssetCollectionSubtypeSmartAlbumUserLibrary
    MUAssetCollectionSubtypeAny                     = NSIntegerMax  // PHAssetCollectionSubtypeAny
};

@class MUAsset;

/**
 @brief
 AssetCollection表示资源集合(相册)，iOS8之前版本为ALAssetsGroup，iOS8以上(包括)对应PHAssetCollection对象
 */
@interface MUAssetCollection : NSObject

/** 请求预览图 */
- (int32_t)requestPosterImageWithCompletionHandler:(void(^)(UIImage *image, NSDictionary *info))completionHandler;

/** 添加asset */
- (BOOL)addAsset:(MUAsset *)asset;

/** 资源集(相册)PHAssetCollection/ALAssetsGroup */
@property (nonatomic, strong, readonly) id realAssetCollection;
/** 唯一标识PHAssetCollection.localIdentifier/ALAssetsGroup.URL.absoluteString */
@property (nonatomic, copy, readonly) NSString *localIdentifier;
/** ALAssetsGroup.URL */
@property (nonatomic, copy, readonly) NSURL *url;
/** 标题名称 */
@property (nonatomic, copy, readonly) NSString *title;
/** 预览缩略图 */
@property (nonatomic, strong, readonly) UIImage *posterImage;
/** 资源集(相册)类型PHAssetCollection.assetCollectionType/ALAssetsGroup.ALAssetsGroupType */
@property (nonatomic, assign, readonly) MUAssetCollectionType type;
/** 资源集(相册)子类型PHAssetCollection。assetCollectionSubtype/ALAssetsGroup无 */
@property (nonatomic, assign, readonly) MUAssetCollectionSubtype subType NS_AVAILABLE_IOS(8_0);
/** 资源总数量 */
@property (nonatomic, assign, readonly) NSInteger numberOfAssets;

/** 资源集合 */
@property (nonatomic, readonly) MUAssetFetchResult *fetchResult;

@end
