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
#import "MUAssetFetchResult.h"

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

typedef NS_ENUM(NSInteger, MUImageContentMode) {
    MUImageContentModeAspectFit     = 0,    // Default 同PHImageContentModeAspectFit
    MUImageContentModeAspectFill    = 1,    // 缩略图时用 同PHImageContentModeAspectFill
};

/** 图片类型 */
typedef enum : NSUInteger {
    MUAssetImageTypeThumbnail,              // 缩略图 ALAsset.thumbnail，PHAsset(targetSize = library.thumbnailSize)
    MUAssetImageTypeAspectRatioThumbnail,   // 缩略图保持纵横比 ALAsset.aspectRatioThumbnail，PHAsset(targetSize = library.thumbnailSize)

    MUAssetImageTypeFullScreen,             // 适合屏幕尺寸的全屏图，速度快但尺寸过大有可能超过targetSize，适用于快速浏览查看图片 ALAsset.fullScreenImage，PHAsset(targetSize=fullScreenImageSize)
    MUAssetImageTypeFullScreenEx,           // MUAssetImageTypeFullScreen扩展, 对超长图做优化
    MUAssetImageTypeExactFullScreenEx,      // MUAssetImageTypeFullScreenEx的PHAsset取图过大优化，获取精确的尺寸适用于最终生成图片 PHAsset(resizeMode=PHImageRequestOptionsResizeModeExact)，
    MUAssetImageTypeOriginal,               // 没处理的原始高清图 适用于获取未调整的高清原图 ALAsset.fullResolutionImage，PHAsset(targetSize=PHImageManagerMaximumSize, version=PHImageRequestOptionsVersionUnadjusted)
    MUAssetImageTypeOriginalAdjusted        // 包含所有调整和修改的原始图 ALAsset.fullResolutionImage做AdjustmentXMP调整，PHAsset(targetSize=PHImageManagerMaximumSize, version=PHImageRequestOptionsVersionCurrent)
} MUAssetImageType;


typedef void (^MUAssetsLibraryResultHandler)(UIImage *image, NSDictionary *info);
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

/** 请求缩略图 */
- (int32_t)requestThumbnailForAsset:(MUAsset *)asset resultHandler:(MUAssetsLibraryResultHandler)resultHandler;

/** 请求图片按类型 适用于快速浏览查看大图 (iOS8 PHImageManager返回的非缩略图需要调整方向) */
- (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler;
/** 请求图片按类型、是否调整方向 适用于最终获取图片 */
- (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler;

/** 请求图片按targetSize、contentMode、options */
- (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(MUAssetsLibraryResultHandler)resultHandler NS_AVAILABLE_IOS(8_0);
/** 请求图片按targetSize、contentMode、options、fixOrientation */
- (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler NS_AVAILABLE_IOS(8_0);

/** 取消异步图片请求 */
- (void)cancelImageRequest:(int32_t)requestID NS_AVAILABLE_IOS(8_0);

/** 同步请求图片 */
- (UIImage *)imageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType;
/** 同步请求图片 PHAsset */
- (UIImage *)imageForPHAsset:(PHAsset *)asset imageType:(MUAssetImageType)imageType NS_AVAILABLE_IOS(8_0);
/** 同步请求图片 ALAsset */
- (UIImage *)imageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType;

/** 获取图片通过ALAsset.URL */
- (void)requestImageForALAssetURL:(NSURL *)assetURL imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler;
/** 获取图片通过ALAsset */
- (void)requestImageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler;

/** 获取视频通过MUAsset */
- (int32_t)requestVideoAVAssetForAsset:(MUAsset *)asset resultHandler:(void (^)(AVAsset *asset, NSDictionary *info))resultHandler;


/** 保存图片至相册 */
- (void)writeImage:(UIImage *)image completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;
- (void)writeImage:(UIImage *)image metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;
- (void)writeImageData:(NSData *)imageData metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;

/** 保存视频至相册 */
- (void)writeVideoAtURL:(NSURL *)url completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;
- (void)createAssetCollectionWithTitle:(NSString *)title completionHandler:(void(^)(MUAssetCollection *assetCollection, NSError *error))completionHandler;


/** 导出视频通过MUAsset */
- (void)exportVideoForAsset:(MUAsset *)asset outputURL:(NSURL *)outputURL completionHandler:(void(^)(BOOL success))completionHandler;
/** 导出视频通过AVAsset */
- (void)exportVideoForAVAsset:(AVAsset *)avAsset presetName:(NSString *)presetName outputURL:(NSURL *)outputURL maxLength:(NSInteger)maxLength completionHandler:(void(^)(BOOL success))completionHandler;


/** 获取Asset通过LocalIdentifier */
- (void)requestAssetWithLocalIdentifier:(NSString *)localIdentifier completionHandler:(void (^)(MUAsset *asset))completionHandler;
/** 获取Asset通过Asset URL */
- (void)requestAssetWithAssetURL:(NSURL *)assetURL completionHandler:(void (^)(MUAsset *asset))completionHandler;


/** 获取资源的Metadata */
- (void)requestMetadataWithAsset:(MUAsset *)asset completionHandler:(void (^)(NSDictionary *metadata))completionHandler;


/** 开始图片缓存 */
- (void)startCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType NS_AVAILABLE_IOS(8_0);
/** 开始缩略图缓存 */
- (void)startCachingThumbnailForAssets:(NSArray *)assets NS_AVAILABLE_IOS(8_0);

/** 停止图片缓存 */
- (void)stopCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType NS_AVAILABLE_IOS(8_0);
/** 停止缩略图缓存 */
- (void)stopCachingThumbnailForAssets:(NSArray *)assets NS_AVAILABLE_IOS(8_0);
/** 停止所有图片缓存 */
- (void)stopCachingImagesForAllAssets NS_AVAILABLE_IOS(8_0);


// request image options
/** 视频忽略低质量图(视频的低质量图带有视频标识水印) 默认 Yes */
@property (nonatomic, assign) BOOL ignoreDegradedImageForVideo NS_AVAILABLE_IOS(8_0);
/** 缩略图大小 默认 150x150 */
@property (nonatomic, assign) CGSize thumbnailSize NS_AVAILABLE_IOS(8_0);
/** 全屏图大小 默认 Screen.size * Screen.scale */
@property (nonatomic, assign) CGSize fullScreenImageSize NS_AVAILABLE_IOS(8_0);
/** 超长图比例 默认 3.0 */
@property (nonatomic, assign) CGFloat longImageAspectRation;


// fetch assetCollection options
/** 允许空相册 */
@property (nonatomic, assign) BOOL allowEmptyAlbums;
/** 用于 8.0~8.1 版本的所有照片相册标题 默认为"所有照片" */
@property (nonatomic, copy) NSString *allPhotosAssetCollectionTitle NS_AVAILABLE_IOS(8_0);

@property (nonatomic, strong, readonly) ALAssetsLibrary *assetsLibrary;
@property (nonatomic, strong, readonly) PHCachingImageManager *imageManager NS_AVAILABLE_IOS(8_0);

@end

