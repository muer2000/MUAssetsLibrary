//
//  MUAssetImageManager.m
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/21.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import "MUAssetImageManager.h"
#import "MUAssetsLibrary.h"

static CGSize kFullScreenImageSize = {640.0, 960.0};
static CGSize kThumbnailSize = {150.0, 150.0};
static BOOL kIgnoreDegradedImageForVideo = YES;
static CGFloat kLongImageAspectRation = 3.0;

#define dispatch_main_sync_safe(block)\
    if ([NSThread isMainThread])\
    {\
        block();\
    }\
    else\
    {\
        dispatch_sync(dispatch_get_main_queue(), block);\
    }

@interface UIImage (MUPrivate)

- (UIImage *)mu_fixOrientation;

@end

@implementation MUAssetImageManager

+ (void)initialize
{
    CGFloat maxScale = MIN([UIScreen mainScreen].scale, 2);
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    kFullScreenImageSize = CGSizeMake(screenSize.width * maxScale, screenSize.height * maxScale);
}

+ (PHCachingImageManager *)sharedImageManager
{
    static PHCachingImageManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PHCachingImageManager alloc] init];
    });
    return instance;
}


#pragma mark - Image Request

+ (int32_t)requestThumbnailForAsset:(MUAsset *)asset resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    return [self requestImageForAsset:asset
                            imageType:MUAssetImageTypeThumbnail
                        resultHandler:resultHandler];
}

+ (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    return [self requestImageForAsset:asset
                            imageType:imageType
                       fixOrientation:NO
                        resultHandler:resultHandler];
}

+ (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if ([asset.realAsset isKindOfClass:[PHAsset class]]) {
        return [self requestImageForPHAsset:asset.realAsset
                                 targetSize:[self p_imageTargetSizeForImageType:imageType phAsset:asset.realAsset]
                                contentMode:[self p_imageContentModeForImageType:imageType]
                                    options:[self p_imageRequestOptionsWithImageType:imageType]
                             fixOrientation:fixOrientation
                              resultHandler:resultHandler];
    }
    else {
        if ([asset.realAsset isKindOfClass:[ALAsset class]]) {
            [self requestImageForALAsset:asset.realAsset imageType:imageType resultHandler:resultHandler];
        }
        else {
            resultHandler(nil, nil);
        }
        return 0;
    }
}

+ (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    return [self requestImageForPHAsset:asset
                             targetSize:targetSize
                            contentMode:contentMode
                                options:options
                         fixOrientation:NO
                          resultHandler:resultHandler];
}

+ (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if (!asset || !asset.localIdentifier) {
        resultHandler(nil, nil);
        return 0;
    }
    return [[self sharedImageManager] requestImageForAsset:asset
                                    targetSize:targetSize
                                   contentMode:(PHImageContentMode)contentMode
                                       options:options
                                 resultHandler:^(UIImage *result, NSDictionary *info)
            {
                BOOL isDegraded = ([[info objectForKey:PHImageResultIsDegradedKey] intValue] == 1);
                // 视频忽略低质量图(视频的低质量图带有视频标识水印)
                if (kIgnoreDegradedImageForVideo && asset.mediaType == PHAssetMediaTypeVideo) {
                    if (!isDegraded) {
                        dispatch_main_sync_safe(^{
                            resultHandler(result, info);
                        });
                    }
                    return;
                }
                
                // 照片流里的资源获取不到原图需要从iCloud下载，故先用缩略图替代
                if (!isDegraded && !result) {
                    [self p_requestiCloudImageForPHAsset:asset
                                              targetSize:targetSize
                                             contentMode:contentMode
                                                 options:options
                                          fixOrientation:fixOrientation
                                           resultHandler:resultHandler];
                    return;
                }
                
                UIImage *imageResult = result;
                // 非缩略图需要调整方向
                if (imageResult && !isDegraded && fixOrientation) {
                    imageResult = [imageResult mu_fixOrientation];
                }
                
                dispatch_main_sync_safe(^{
                    resultHandler(imageResult, info);
                });
            }];
}

+ (void)cancelImageRequest:(int32_t)requestID
{
    if ([MUAssetsLibrary authorizationStatus] != MUPHAuthorizationStatusAuthorized) {
        return;
    }
    if (requestID > 0 && [self sharedImageManager]) {
        [[self sharedImageManager] cancelImageRequest:requestID];
    }
}

+ (void)requestImageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return;
    }
    if ([MUAssetsLibrary authorizationStatus] != MUPHAuthorizationStatusAuthorized) {
        resultHandler(nil, nil);
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        UIImage *image = [self imageForALAsset:asset imageType:imageType];
        dispatch_main_sync_safe(^{
            if (resultHandler) {
                resultHandler(image, nil);
            }
        });
    });
}


#pragma mark - Sync request image

+ (UIImage *)imageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType
{
    if ([asset.realAsset isKindOfClass:[PHAsset class]]) {
        return [self imageForPHAsset:asset.realAsset imageType:imageType];
    }
    else if ([asset.realAsset isKindOfClass:[ALAsset class]]) {
        return [self imageForALAsset:asset.realAsset imageType:imageType];
    }
    return nil;
}

+ (UIImage *)imageForPHAsset:(PHAsset *)asset imageType:(MUAssetImageType)imageType
{
    PHImageRequestOptions *options = [self p_imageRequestOptionsWithImageType:imageType];
    if (!options) {
        options = [[PHImageRequestOptions alloc] init];
    }
    options.synchronous = YES;
    
    __block UIImage *result = nil;
    [self requestImageForPHAsset:asset
                      targetSize:[self p_imageTargetSizeForImageType:imageType phAsset:asset]
                     contentMode:[self p_imageContentModeForImageType:imageType]
                         options:options
                  fixOrientation:YES
                   resultHandler:^(UIImage *image, NSDictionary *info) {
                       result = image;
                   }];
    return result;
}

+ (UIImage *)imageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType
{
    if (!asset) {
        return nil;
    }
    UIImage *image = nil;
    ALAssetRepresentation *rep = asset.defaultRepresentation;
    switch (imageType) {
        case MUAssetImageTypeThumbnail:
            image = [UIImage imageWithCGImage:asset.thumbnail];
            break;
        case MUAssetImageTypeAspectRatioThumbnail:
            image = [UIImage imageWithCGImage:asset.aspectRatioThumbnail];
            break;
        case MUAssetImageTypeFullScreen:
            image = [UIImage imageWithCGImage:rep.fullScreenImage];
            break;
        case MUAssetImageTypeFullScreenEx:
        case MUAssetImageTypeExactFullScreenEx:
            if ([self p_imageSizeIsLong:rep.dimensions]) {
                return [self imageForALAsset:asset imageType:MUAssetImageTypeOriginalAdjusted];
            }
            else {
                image = [self imageForALAsset:asset imageType:MUAssetImageTypeFullScreen];
            }
            break;
        case MUAssetImageTypeOriginal:
            image = [UIImage imageWithCGImage:rep.fullResolutionImage];
            break;
        default: {
            CGImageRef imageRef = CGImageRetain(rep.fullResolutionImage);
            NSString *adjustment = [rep.metadata objectForKey:@"AdjustmentXMP"];
            if (adjustment) {
                NSData *xmpData = [adjustment dataUsingEncoding:NSUTF8StringEncoding];
                CIImage *image = [CIImage imageWithCGImage:imageRef];
                
                NSError *error = nil;
                NSArray *filterArray = [CIFilter filterArrayFromSerializedXMP:xmpData
                                                             inputImageExtent:image.extent
                                                                        error:&error];
                CIContext *context = [CIContext contextWithOptions:nil];
                if (filterArray && !error) {
                    for (CIFilter *filter in filterArray) {
                        [filter setValue:image forKey:kCIInputImageKey];
                        image = [filter outputImage];
                    }
                    CGImageRelease(imageRef);
                    imageRef = [context createCGImage:image fromRect:[image extent]];
                }
            }
            image = [UIImage imageWithCGImage:imageRef
                                        scale:rep.scale
                                  orientation:(UIImageOrientation)rep.orientation];
            CGImageRelease(imageRef);
            image = [image mu_fixOrientation];
        }
            break;
    }
    if (image == nil && asset.aspectRatioThumbnail) {
        image = [UIImage imageWithCGImage:asset.aspectRatioThumbnail];
    }
    return image;
}


#pragma mark - Video Request

+ (int32_t)requestVideoAVAssetForAsset:(MUAsset *)asset resultHandler:(void (^)(AVAsset *asset, NSDictionary *info))resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if (!asset.localIdentifier) {
        resultHandler(nil, nil);
        return 0;
    }
    if ([asset.realAsset isKindOfClass:[PHAsset class]]) {
        if (!asset.realAsset || ![asset.realAsset isKindOfClass:[PHAsset class]]) {
            resultHandler(nil, nil);
            return 0;
        }
        return [[self sharedImageManager] requestAVAssetForVideo:asset.realAsset options:nil resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info) {
            dispatch_main_sync_safe(^{
                resultHandler(asset, info);
            });
        }];
    }
    else {
        AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:asset.url options:nil];
        resultHandler(avAsset, nil);
        return 0;
    }
}


#pragma mark - Image Cache

+ (void)startCachingThumbnailForAssets:(NSArray *)assets
{
    [self startCachingImagesForAssets:assets imageType:MUAssetImageTypeThumbnail];
}

+ (void)startCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType
{
    if ([MUAssetsLibrary authorizationStatus] != MUPHAuthorizationStatusAuthorized) {
        return;
    }
    NSArray *assetArray = [self p_phAssetsForMUAssets:assets];
    if (assetArray) {
        [[self sharedImageManager] startCachingImagesForAssets:assetArray
                                                    targetSize:[self p_imageTargetSizeForImageType:imageType]
                                                   contentMode:(PHImageContentMode)[self p_imageContentModeForImageType:imageType]
                                                       options:nil];
    }
}

+ (void)stopCachingThumbnailForAssets:(NSArray *)assets
{
    [self stopCachingImagesForAssets:assets imageType:MUAssetImageTypeThumbnail];
}

+ (void)stopCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType
{
    if ([MUAssetsLibrary authorizationStatus] != MUPHAuthorizationStatusAuthorized) {
        return;
    }
    NSArray *assetArray = [self p_phAssetsForMUAssets:assets];
    if (assetArray) {
        [[self sharedImageManager] stopCachingImagesForAssets:assetArray
                                                   targetSize:[self p_imageTargetSizeForImageType:imageType]
                                                  contentMode:(PHImageContentMode)[self p_imageContentModeForImageType:imageType]
                                                      options:nil];
    }
}

+ (void)stopCachingImagesForAllAssets
{
    if ([MUAssetsLibrary authorizationStatus] != MUPHAuthorizationStatusAuthorized) {
        return;
    }
    [[self sharedImageManager] stopCachingImagesForAllAssets];
}


#pragma mark - Private

+ (int32_t)p_requestiCloudImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if (!asset) {
        resultHandler(nil, nil);
        return 0;
    }
    // 先获取缩略图
    [[self sharedImageManager] requestImageForAsset:asset
                             targetSize:[self p_imageTargetSizeForImageType:MUAssetImageTypeThumbnail]
                            contentMode:(PHImageContentMode)[self p_imageContentModeForImageType:MUAssetImageTypeThumbnail]
                                options:options
                          resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info)
     {
         dispatch_main_sync_safe(^{
             NSLog(@"*** iCloud thumbnail %@, %@", info, NSStringFromCGSize(result.size));
             resultHandler(result, info);
         });
     }];
    
    // 获取iCloud照片流原图
    PHImageRequestOptions *tmpOptions = options;
    if (tmpOptions == nil) {
        tmpOptions = [[PHImageRequestOptions alloc] init];
    }
    tmpOptions.networkAccessAllowed = YES;
    tmpOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    
    return [[self sharedImageManager] requestImageForAsset:asset
                                    targetSize:kFullScreenImageSize
                                   contentMode:PHImageContentModeAspectFit
                                       options:tmpOptions
                                 resultHandler:^(UIImage *result, NSDictionary *info)
            {
                BOOL isDegraded = ([[info objectForKey:PHImageResultIsDegradedKey] intValue] == 1);
                UIImage *imageResult = result;
                if (imageResult && !isDegraded && fixOrientation) {
                    imageResult = [imageResult mu_fixOrientation];
                }
                dispatch_main_sync_safe(^{
                    NSLog(@"*** iCloud image %@, %@", info, NSStringFromCGSize(result.size));
                    resultHandler(imageResult, info);
                });
            }];
}

+ (BOOL)p_imageSizeIsLong:(CGSize)size
{
    return (size.width > 0 && size.height / size.width > kLongImageAspectRation);
}

+ (PHImageRequestOptions *)p_imageRequestOptionsWithImageType:(MUAssetImageType)imageType
{
    PHImageRequestOptions *options = nil;
    // 不加resizeMode选项默认获取的FullScreen图片太大，故需要设置resizeMode参数
    if (imageType == MUAssetImageTypeExactFullScreenEx) {
        options = [[PHImageRequestOptions alloc] init];
        options.resizeMode = PHImageRequestOptionsResizeModeExact;
    }
    else if (imageType == MUAssetImageTypeOriginal) {
        options = [[PHImageRequestOptions alloc] init];
        options.version = PHImageRequestOptionsVersionUnadjusted;
    }
    else if (imageType == MUAssetImageTypeThumbnail || imageType == MUAssetImageTypeAspectRatioThumbnail) {
//        options = [[PHImageRequestOptions alloc] init];
//        options.resizeMode = PHImageRequestOptionsResizeModeFast;
    }
    return options;
}

+ (CGSize)p_imageTargetSizeForImageType:(MUAssetImageType)imageType phAsset:(PHAsset *)phAsset
{
    switch (imageType) {
        case MUAssetImageTypeThumbnail:
        case MUAssetImageTypeAspectRatioThumbnail:
            return kThumbnailSize;
        case MUAssetImageTypeFullScreen:
            return kFullScreenImageSize;
        case MUAssetImageTypeFullScreenEx: {
            if (phAsset && [self p_imageSizeIsLong:CGSizeMake(phAsset.pixelWidth, phAsset.pixelHeight)]) {
                return PHImageManagerMaximumSize;
            }
            return kFullScreenImageSize;
        }
        case MUAssetImageTypeExactFullScreenEx: {
            if (phAsset && [self p_imageSizeIsLong:CGSizeMake(phAsset.pixelWidth, phAsset.pixelHeight)]) {
                return PHImageManagerMaximumSize;
            }
            return CGSizeMake(kFullScreenImageSize.width * 2, kFullScreenImageSize.height * 2);
        }
        default:
            return PHImageManagerMaximumSize;
    }
}

+ (CGSize)p_imageTargetSizeForImageType:(MUAssetImageType)imageType
{
    return [self p_imageTargetSizeForImageType:imageType phAsset:nil];
}

+ (MUImageContentMode)p_imageContentModeForImageType:(MUAssetImageType)imageType
{
    if (imageType == MUAssetImageTypeThumbnail || imageType == MUAssetImageTypeAspectRatioThumbnail) {
        return MUImageContentModeAspectFill;
    }
    return MUImageContentModeAspectFit;
}

+ (NSArray *)p_phAssetsForMUAssets:(NSArray *)MUAssets
{
    if (MUAssets.count == 0) {
        return nil;
    }
    NSMutableArray *assetArray = [NSMutableArray arrayWithCapacity:MUAssets.count];
    for (MUAsset *itemAsset in MUAssets) {
        if (itemAsset.realAsset && [itemAsset.realAsset isKindOfClass:[PHAsset class]]) {
            [assetArray addObject:itemAsset.realAsset];
        }
    }
    return assetArray;
}

@end


@implementation UIImage (MUPrivate)

- (UIImage *)mu_fixOrientation {
    
    // No-op if the orientation is already correct
    if (self.imageOrientation == UIImageOrientationUp) return self;
    
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (self.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, self.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, self.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (self.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, self.size.width, self.size.height,
                                             CGImageGetBitsPerComponent(self.CGImage), 0,
                                             CGImageGetColorSpace(self.CGImage),
                                             CGImageGetBitmapInfo(self.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (self.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.height,self.size.width), self.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.width,self.size.height), self.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

@end