//
//  MUAsset.h
//  MUAssetsLibrary
//
//  Created by Muer on 15/9/24.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString * const PHAssetURLScheme;   // photos-framework
extern NSString * const ALAAssetURLScheme;  // assets-library

/** 资源类型 */
typedef NS_ENUM(NSInteger, MUAssetMediaType) {
    MUAssetMediaTypeAny     = -1,
    MUAssetMediaTypeUnknown = 0,
    MUAssetMediaTypeImage   = 1,
    MUAssetMediaTypeVideo   = 2,
    MUAssetMediaTypeAudio   = 3,
};

@class CLLocation;

/**
 @brief
 Asset表示照片库中的一个图片或视频资源对象，iOS8之前版本对应ALAsset对象，iOS8以上对应PHAsset对象
 */
@interface MUAsset : NSObject

/** PHAsset/ALAsset */
@property (nonatomic, strong, readonly) id realAsset;
/** 唯一标识 PHAsset.localIdentifier; ALAsset.URL.absoluteString */
@property (nonatomic, copy, readonly) NSString *localIdentifier;
/** URL PHAsset = PHAssetURLScheme:// + localIdentifier; ALAsset.URL */
@property (nonatomic, copy, readonly) NSURL *url;
/** 缩略图 ALAsset.thumbnail */
@property (nonatomic, strong, readonly) UIImage *thumbnail;
/** 尺寸大小 */
@property (nonatomic, assign, readonly) CGSize dimensions;
/** 创建时间 */
@property (nonatomic, strong, readonly) NSDate *creationDate;
/** 地理位置 */
@property (nonatomic, strong, readonly) CLLocation *location;
/** 视频持续时间 */
@property (nonatomic, assign, readonly) NSTimeInterval duration;
/** 资源类型 */
@property (nonatomic, assign, readonly) MUAssetMediaType mediaType;

@end
