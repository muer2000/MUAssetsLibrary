//
//  MUAssetsLibrary.h
//  MUAssetsLibrary
//
//  Created by Muer on 14-9-10.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "MUAsset.h"
#import "MUAssetCollection.h"

@class AVAsset;

extern NSString * const MUAssetsLibraryChangedNotification;

extern CGSize const MUImageManagerMaximumSize NS_AVAILABLE_IOS(8_0);
extern NSString * const MUImageResultIsInCloudKey NS_AVAILABLE_IOS(8_0);
extern NSString * const MUImageResultIsDegradedKey NS_AVAILABLE_IOS(8_0);
extern NSString * const MUImageResultRequestIDKey NS_AVAILABLE_IOS(8_0);
extern NSString * const MUImageCancelledKey NS_AVAILABLE_IOS(8_0);
extern NSString * const MUImageErrorKey NS_AVAILABLE_IOS(8_0);

typedef NS_ENUM(NSInteger, MUPHAuthorizationStatus) {
    MUPHAuthorizationStatusNotDetermined = 0,
    MUPHAuthorizationStatusRestricted,
    MUPHAuthorizationStatusDenied,
    MUPHAuthorizationStatusAuthorized
};

typedef void (^MUAssetsLibraryWriteCompletionHandler)(MUAsset *asset, NSError *error);


/**
 @brief
 MUAssetsLibrary资源库，分别对应ALAssetsLibrary和PHPhotoLibrary
 */
@interface MUAssetsLibrary : NSObject

/** 照片库授权状态 */
+ (MUPHAuthorizationStatus)authorizationStatus;
/** 请求访问照片库权限 */
+ (void)requestPhotoLibraryPermissionWithCompletionHandler:(void (^)(BOOL granted))handler;

+ (BOOL)isAssetURL:(NSURL *)url;

+ (instancetype)sharedLibrary;

/** 请求照片库的资源集(相册) */
- (void)requestAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray<MUAssetCollection *> *assetCollections, NSError *error))completionHandler;

/** 请求照片库海报预览图 */
- (void)requestPhotoLibraryPosterImageForMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(UIImage *image))completionHandler;

/** 保存图片至相册 */
- (void)writeImage:(UIImage *)image completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;
- (void)writeImage:(UIImage *)image metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;

/** 保存视频至相册 */
- (void)writeVideoAtURL:(NSURL *)url completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;

/** 创建相册 */
- (void)createAssetCollectionWithTitle:(NSString *)title completionHandler:(void(^)(MUAssetCollection *assetCollection, NSError *error))completionHandler;
/** 请求相册通过标题 */
- (void)requestAssetCollectionsWithTitle:(NSString *)title completionHandler:(void (^)(MUAssetCollection *assetCollection, NSError *error))completionHandler;

/** 获取Asset通过LocalIdentifier */
- (void)requestAssetWithLocalIdentifier:(NSString *)localIdentifier completionHandler:(void (^)(MUAsset *asset))completionHandler;
/** 获取Asset通过Asset URL */
- (void)requestAssetWithAssetURL:(NSURL *)assetURL completionHandler:(void (^)(MUAsset *asset))completionHandler;

/** 获取Asset的Metadata */
- (void)requestMetadataWithAsset:(MUAsset *)asset completionHandler:(void (^)(NSDictionary *metadata))completionHandler;

/** 允许空相册 */
@property (nonatomic, assign) BOOL allowEmptyAlbums;
/** 用于 8.0~8.1 版本的所有照片相册标题 默认为"所有照片" */
@property (nonatomic, copy) NSString *allPhotosAssetCollectionTitle NS_AVAILABLE_IOS(8_0);

@end

