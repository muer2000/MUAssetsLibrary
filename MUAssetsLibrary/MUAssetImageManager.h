//
//  MUAssetImageManager.h
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/21.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "MUAsset.h"

typedef NS_ENUM(NSInteger, MUImageContentMode) {
    MUImageContentModeAspectFit     = 0,    // 同PHImageContentModeAspectFit
    MUImageContentModeAspectFill    = 1,    // 同PHImageContentModeAspectFill
};

typedef enum : NSUInteger {
    MUAssetImageTypeThumbnail,              // 缩略图 ALAsset.thumbnail，PHAsset(targetSize = library.thumbnailSize)
    MUAssetImageTypeAspectRatioThumbnail,   // 缩略图保持纵横比 ALAsset.aspectRatioThumbnail，PHAsset(targetSize = library.thumbnailSize)
    
    MUAssetImageTypeFullScreen,             // 适合屏幕尺寸的全屏图，速度快但尺寸过大有可能超过targetSize，适用于快速浏览查看图片 ALAsset.fullScreenImage，PHAsset(targetSize=fullScreenImageSize)
    MUAssetImageTypeFullScreenEx,           // MUAssetImageTypeFullScreen扩展, 对超长图做优化
    MUAssetImageTypeExactFullScreenEx,      // MUAssetImageTypeFullScreenEx的PHAsset取图过大优化，获取精确的尺寸适用于最终生成图片 PHAsset(resizeMode=PHImageRequestOptionsResizeModeExact)
    
    MUAssetImageTypeOriginal,               // 没处理的原始高清图 适用于获取未调整的高清原图 ALAsset.fullResolutionImage，PHAsset(targetSize=PHImageManagerMaximumSize, version=PHImageRequestOptionsVersionUnadjusted)
    MUAssetImageTypeOriginalAdjusted        // 包含所有调整和修改的原始图 ALAsset.fullResolutionImage做AdjustmentXMP调整，PHAsset(targetSize=PHImageManagerMaximumSize, version=PHImageRequestOptionsVersionCurrent)
} MUAssetImageType;

typedef void (^MUAssetsLibraryResultHandler)(UIImage *image, NSDictionary *info);


@interface MUAssetImageManager : NSObject

//** 请求缩略图 */
+ (int32_t)requestThumbnailForAsset:(MUAsset *)asset resultHandler:(MUAssetsLibraryResultHandler)resultHandler;
/** 请求图片按类型 适用于快速浏览查看大图 (iOS8 PHImageManager返回的非缩略图需要调整方向) */
+ (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler;
/** 请求图片按类型、是否调整方向 适用于最终获取图片 */
+ (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler;

/** 请求图片按targetSize、contentMode、options */
+ (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(MUAssetsLibraryResultHandler)resultHandler NS_AVAILABLE_IOS(8_0);
/** 请求图片按targetSize、contentMode、options、fixOrientation */
+ (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler NS_AVAILABLE_IOS(8_0);

/** 取消异步图片请求 */
+ (void)cancelImageRequest:(int32_t)requestID NS_AVAILABLE_IOS(8_0);

/** 获取图片通过ALAsset */
+ (void)requestImageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler;

/** 同步请求图片 */
+ (UIImage *)imageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType;
/** 同步请求图片 PHAsset */
+ (UIImage *)imageForPHAsset:(PHAsset *)asset imageType:(MUAssetImageType)imageType NS_AVAILABLE_IOS(8_0);
/** 同步请求图片 ALAsset */
+ (UIImage *)imageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType;

/** 获取视频通过MUAsset */
+ (int32_t)requestVideoAVAssetForAsset:(MUAsset *)asset resultHandler:(void (^)(AVAsset *asset, NSDictionary *info))resultHandler;

/** 开始图片缓存 */
+ (void)startCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType NS_AVAILABLE_IOS(8_0);
/** 开始缩略图缓存 */
+ (void)startCachingThumbnailForAssets:(NSArray *)assets NS_AVAILABLE_IOS(8_0);

/** 停止图片缓存 */
+ (void)stopCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType NS_AVAILABLE_IOS(8_0);
/** 停止缩略图缓存 */
+ (void)stopCachingThumbnailForAssets:(NSArray *)assets NS_AVAILABLE_IOS(8_0);
/** 停止所有图片缓存 */
+ (void)stopCachingImagesForAllAssets NS_AVAILABLE_IOS(8_0);

@end
