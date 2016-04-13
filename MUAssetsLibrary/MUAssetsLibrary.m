//
//  MUAssetsLibrary.m
//  MUAssetsLibrary
//
//  Created by Muer on 14-9-10.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import "MUAssetsLibrary.h"
#import <CoreLocation/CoreLocation.h>
#import <AVFoundation/AVFoundation.h>

typedef NSString * (^MUAssetWritePerformChangeBlock) (void);

NSString * const MUAssetsLibraryChangedNotification = @"MUAssetsLibraryChangedNotification";

CGSize const MUImageManagerMaximumSize = {-1, -1};
NSString * const MUImageResultIsInCloudKey = @"PHImageResultIsInCloudKey";
NSString * const MUImageResultIsDegradedKey = @"PHImageResultIsDegradedKey";
NSString * const MUImageResultRequestIDKey = @"PHImageResultRequestIDKey";
NSString * const MUImageCancelledKey = @"PHImageCancelledKey";
NSString * const MUImageErrorKey = @"PHImageErrorKey";

#define dispatch_main_sync_safe(block)\
    if ([NSThread isMainThread])\
    {\
        block();\
    }\
    else\
    {\
        dispatch_sync(dispatch_get_main_queue(), block);\
    }

#define kIsiOS8 (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_7_1)

#define kAuthorizationStatus ([MUAssetsLibrary authorizationStatus])
#define kMUAssetsLibraryUnauthorized (kAuthorizationStatus == MUPHAuthorizationStatusDenied ||\
    kAuthorizationStatus == MUPHAuthorizationStatusRestricted)


@interface UIImage (Private)
- (UIImage *)p_fixOrientation;
@end

@interface MUAsset ()

+ (instancetype)p_assetWithPHAsset:(PHAsset *)phAsset;
+ (instancetype)p_assetWithALAsset:(ALAsset *)alAsset;

@end

@interface MUAssetCollection ()

+ (instancetype)p_assetCollectionWithAssetsGroup:(ALAssetsGroup *)group;
+ (instancetype)p_assetCollectionWithPHAssetCollection:(PHAssetCollection *)phAssetCollection fetchOptions:(PHFetchOptions *)fetchOptions;
+ (instancetype)p_allPhotosCollectionWithTitle:(NSString *)title fetchOptions:(PHFetchOptions *)fetchOptions;

@property (nonatomic, assign) NSInteger sortIndex;

@end


@interface MUAssetsLibrary() <PHPhotoLibraryChangeObserver>

- (void)p_requestPHAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray *assetCollections, NSError *error))completionHandler;
- (void)p_requestALAAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray *assetCollections, NSError *error))completionHandler;

- (int32_t)p_requestiCloudImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler;
- (void)p_requestAssetWithALAAssetURL:(NSURL *)alaAssetURL completionHandler:(void (^)(MUAsset *asset))completionHandler;
- (void)p_requestAssetWithPHLocalIdentifier:(NSString *)phLocalIdentifier completionHandler:(void (^)(MUAsset *asset))completionHandler;

- (BOOL)p_imageSizeIsLong:(CGSize)size;

- (PHImageRequestOptions *)p_imageRequestOptionsWithImageType:(MUAssetImageType)imageType;
- (CGSize)p_imageTargetSizeForImageType:(MUAssetImageType)imageType phAsset:(PHAsset *)phAsset;
- (CGSize)p_imageTargetSizeForImageType:(MUAssetImageType)imageType;
- (MUImageContentMode)p_imageContentModeForImageType:(MUAssetImageType)imageType;
- (NSArray *)p_phAssetsForMUAssets:(NSArray *)MUAssets;
- (PHFetchOptions *)p_assetFetchOptionsForMediaType:(MUAssetMediaType)mediaType;

- (void)p_writeDataPerformChange:(MUAssetWritePerformChangeBlock)changeBlock completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;
- (void)p_writeImageWithAssetsLibrary:(UIImage *)image completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;
- (void)p_writeVideoWithAssetsLibraryAtURL:(NSURL *)url completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler;

// >= iOS8
@property (nonatomic, strong) PHCachingImageManager *imageManager;
// < iOS8
@property (nonatomic, strong) ALAssetsLibrary *assetsLibrary;

@property (nonatomic, strong) NSArray *assetCollectionFetchResultArray;
@property (nonatomic, strong) MUAssetCollection *currentAssetCollection;
@property (nonatomic, strong) PHFetchOptions *assetFetchOptions;

@property (nonatomic, assign) MUAssetMediaType currentMediaType;
@property (nonatomic, assign) BOOL photoLibraryChanged;

@end


@implementation MUAssetsLibrary

+ (MUPHAuthorizationStatus)authorizationStatus
{
    if (kIsiOS8) {
        return (MUPHAuthorizationStatus)[PHPhotoLibrary authorizationStatus];
    }
    return (MUPHAuthorizationStatus)[ALAssetsLibrary authorizationStatus];
}

+ (void)requestPhotoLibraryPermissionWithCompletionHandler:(void (^)(BOOL granted))handler
{
    MUPHAuthorizationStatus status = [MUAssetsLibrary authorizationStatus];
    if (status == MUPHAuthorizationStatusNotDetermined) {
        if (kIsiOS8) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_main_sync_safe(^{
                    if (handler) {
                        handler(status == PHAuthorizationStatusAuthorized);
                    }
                });
            }];
        }
        else {
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                dispatch_main_sync_safe(^{
                    if (handler) {
                        handler(YES);
                    }
                    *stop = YES;
                });
            } failureBlock:^(NSError *error) {
                dispatch_main_sync_safe(^{
                    if (handler) {
                        handler(NO);
                    }
                });
            }];
        }
    }
    else {
        if (handler) {
            handler(status == MUPHAuthorizationStatusAuthorized);
        }
    }
}

+ (NSError *)unauthorizedError
{
    return [NSError errorWithDomain:@"photo library unauthorized" code:-1 userInfo:nil];
}

+ (BOOL)isAssetURL:(NSURL *)url
{
    NSString *urlScheme = [[url scheme] lowercaseString];
    return [urlScheme isEqualToString:PHAssetURLScheme] || [urlScheme isEqualToString:ALAAssetURLScheme];
}

+ (instancetype)sharedLibrary
{
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}


#pragma mark - lifecycle

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.allPhotosAssetCollectionTitle = NSLocalizedString(@"所有照片", nil);
        self.thumbnailSize = CGSizeMake(150, 150);
        self.longImageAspectRation = 3.0;
        self.ignoreDegradedImageForVideo = YES;
        
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        // 忽略2倍以上尺寸
        CGFloat maxScale = MIN([UIScreen mainScreen].scale, 2);
        self.fullScreenImageSize = CGSizeMake(screenSize.width * maxScale, screenSize.height * maxScale);

        if (kIsiOS8) {
            self.imageManager = [[PHCachingImageManager alloc] init];
            [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
        }
        else {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(assetsLibraryChangedNotification:) name:ALAssetsLibraryChangedNotification object:nil];
            self.assetsLibrary = [[ALAssetsLibrary alloc] init];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - fetch AssetCollections

- (void)requestAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray<MUAssetCollection *> *assetCollections, NSError *error))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized) {
        completionHandler(nil, [MUAssetsLibrary unauthorizedError]);
        return;
    }

    if (kIsiOS8) {
        [self p_requestPHAssetCollectionsWithMediaType:mediaType completionHandler:completionHandler];
    }
    else {
        [self p_requestALAAssetCollectionsWithMediaType:mediaType completionHandler:completionHandler];
    }
}

- (void)p_requestALAAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray *assetCollections, NSError *error))completionHandler
{
    __block MUAssetCollection *cameraRollCollection = nil;
    NSMutableArray *assetCollections = [NSMutableArray array];
    [_assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group) {
            switch(mediaType) {
                case MUAssetMediaTypeImage: [group setAssetsFilter:[ALAssetsFilter allPhotos]]; break;
                case MUAssetMediaTypeVideo: [group setAssetsFilter:[ALAssetsFilter allVideos]]; break;
                default: [group setAssetsFilter:[ALAssetsFilter allAssets]]; break;
            }
            
            if (self.allowEmptyAlbums || group.numberOfAssets > 0) {
                MUAssetCollection *muAC = [MUAssetCollection p_assetCollectionWithAssetsGroup:group];
                // 是否相机胶卷
                if ([[group valueForProperty:ALAssetsGroupPropertyType] intValue] == ALAssetsGroupSavedPhotos) {
                    cameraRollCollection = muAC;
                }
                else {
                    [assetCollections addObject:muAC];
                }
            }
        }
        // 为空时表示遍历结束
        else {
            // 相机胶卷插入置顶
            if (cameraRollCollection) {
                [assetCollections insertObject:cameraRollCollection atIndex:0];;
            }
            if (completionHandler) {
                completionHandler(assetCollections, nil);
            }
        }
    } failureBlock:^(NSError *error) {
        if (completionHandler) {
            completionHandler(nil, error);
        }
    }];
}

- (void)p_requestPHAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray *assetCollections, NSError *error))completionHandler
{
    // iOS8需要先请求访问相册权限
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_main_sync_safe(^{
                if (status == PHAuthorizationStatusAuthorized) {
                    [self p_requestPHAssetCollectionsWithMediaType:mediaType completionHandler:completionHandler];
                }
                else {
                    if (completionHandler) {
                        completionHandler(nil, [MUAssetsLibrary unauthorizedError]);
                    }
                }
            });
        }];
        return;
    }

    self.assetFetchOptions = [self p_assetFetchOptionsForMediaType:mediaType];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 获得相册结果集
        NSArray *fetchResults = [MUAssetsLibrary p_fetchResultsOfAssetCollection];
        NSMutableArray *assetCollections = [NSMutableArray array];
        BOOL hasCameraRoll = NO;
        for (PHFetchResult *itemAssetCollectionFetchResult in fetchResults) {
            for (PHAssetCollection *itemAssetCollection in itemAssetCollectionFetchResult) {
                // 忽略“视频”相册
                if (mediaType != MUAssetMediaTypeAny && itemAssetCollection.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumVideos) {
                    continue;
                }
                
                // 去掉最近删除资源集，最近删除=1000000201
                if (itemAssetCollection.assetCollectionType == PHAssetCollectionTypeSmartAlbum &&
                    itemAssetCollection.assetCollectionSubtype > 10000) {
                    continue;
                }
                
                MUAssetCollection *muAC = [MUAssetCollection p_assetCollectionWithPHAssetCollection:itemAssetCollection fetchOptions:self.assetFetchOptions];

                if (!hasCameraRoll && itemAssetCollection.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumUserLibrary) {
                    hasCameraRoll = YES;
                }
                
                // 忽略空相册
                if (self.allowEmptyAlbums || muAC.numberOfAssets > 0) {
                    [assetCollections addObject:muAC];
                }
            }
        }
        
        // 没有“相机胶卷”时创建“所有照片”相册集并置顶
        if (!hasCameraRoll) {
            MUAssetCollection *allPhotosAC = [MUAssetCollection p_allPhotosCollectionWithTitle:self.allPhotosAssetCollectionTitle fetchOptions:self.assetFetchOptions];
            if (allPhotosAC.numberOfAssets > 0) {
                [assetCollections insertObject:allPhotosAC atIndex:0];
            }
        }

        NSSortDescriptor *sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"sortIndex" ascending:YES];
        [assetCollections sortUsingDescriptors:@[sortDesc]];
        
        dispatch_main_sync_safe(^{
            if (completionHandler) {
                completionHandler(assetCollections, nil);
            }
        });
    });
}


#pragma mark - Poster Image

- (void)requestPhotoLibraryPosterImageForMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(UIImage *image))completionHandler
{
    if (!completionHandler) {
        return;
    }
    
    if (kMUAssetsLibraryUnauthorized) {
        completionHandler(nil);
        return;
    }
    
    if (kIsiOS8) {
        if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                dispatch_main_sync_safe(^{
                    if (status == PHAuthorizationStatusAuthorized) {
                        [self requestPhotoLibraryPosterImageForMediaType:mediaType completionHandler:completionHandler];
                    }
                    else {
                        completionHandler(nil);
                    }
                });
            }];
            return;
        }
        
        PHFetchOptions *options = [self p_assetFetchOptionsForMediaType:mediaType];
        PHAsset *firstAsset = nil;
        // 所有照片
        PHFetchResult *assetFetchResult = [PHAsset fetchAssetsWithMediaType:(PHAssetMediaType)mediaType options:options];
        if (assetFetchResult.count > 0) {
            firstAsset = assetFetchResult.firstObject;
        }
        else {
            // 所有照片相册集为空有可能最近删除里有数据
            PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
            for (PHAssetCollection *itemAssetCollection in smartAlbums) {
                PHFetchResult *assetFetchResult = [PHAsset fetchAssetsInAssetCollection:itemAssetCollection options:options];
                if (assetFetchResult.count > 0) {
                    firstAsset = assetFetchResult.firstObject;
                    break;
                }
            }
        }
        if (firstAsset) {
            [_imageManager requestImageForAsset:firstAsset targetSize:self.thumbnailSize contentMode:PHImageContentModeAspectFill options:nil resultHandler:^(UIImage *result, NSDictionary *info) {
                if ([[info objectForKey:PHImageResultIsDegradedKey] integerValue] != 1) {
                    completionHandler(result);
                }
            }];
        }
        else {
            completionHandler(nil);
        }
    }
    else {
        __block NSMutableArray *groupArray = [NSMutableArray array];
        [_assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            if (group) {
                switch(mediaType) {
                    case MUAssetMediaTypeImage: [group setAssetsFilter:[ALAssetsFilter allPhotos]]; break;
                    case MUAssetMediaTypeVideo: [group setAssetsFilter:[ALAssetsFilter allVideos]]; break;
                    default: [group setAssetsFilter:[ALAssetsFilter allAssets]]; break;
                }
                if (group.numberOfAssets > 0) {
                    if ([[group valueForProperty:ALAssetsGroupPropertyType] intValue] == ALAssetsGroupSavedPhotos) {
                        [groupArray insertObject:group atIndex:0];
                        *stop = YES;
                    }
                    else {
                        [groupArray addObject:group];
                    }
                }
            }
            else {
                if (groupArray.count > 0) {
                    completionHandler([UIImage imageWithCGImage:((ALAssetsGroup *)groupArray.firstObject).posterImage]);
                }
                else {
                    completionHandler(nil);
                }
            }
        } failureBlock:^(NSError *error) {
            completionHandler(nil);
        }];
    }
}


#pragma mark - Image Request

- (int32_t)requestThumbnailForAsset:(MUAsset *)asset resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    return [self requestImageForAsset:asset
                            imageType:MUAssetImageTypeThumbnail
                        resultHandler:resultHandler];
}

- (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    return [self requestImageForAsset:asset
                            imageType:imageType
                       fixOrientation:NO
                        resultHandler:resultHandler];
}

- (int32_t)requestImageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler
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
        else if (asset.url) {
            [self requestImageForALAssetURL:asset.url imageType:imageType resultHandler:resultHandler];
        }
        else {
            resultHandler(nil, nil);
        }
        return 0;
    }
}

- (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    return [self requestImageForPHAsset:asset
                             targetSize:targetSize
                            contentMode:contentMode
                                options:options
                         fixOrientation:NO
                          resultHandler:resultHandler];
}

- (int32_t)requestImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if (kMUAssetsLibraryUnauthorized || !asset || !asset.localIdentifier) {
        resultHandler(nil, nil);
        return 0;
    }
    return [_imageManager requestImageForAsset:asset
                                    targetSize:targetSize
                                   contentMode:(PHImageContentMode)contentMode
                                       options:options
                                 resultHandler:^(UIImage *result, NSDictionary *info)
            {
                BOOL isDegraded = ([[info objectForKey:PHImageResultIsDegradedKey] intValue] == 1);
                // 视频忽略低质量图(视频的低质量图带有视频标识水印)
                if (self.ignoreDegradedImageForVideo && asset.mediaType == PHAssetMediaTypeVideo) {
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
                    imageResult = [imageResult p_fixOrientation];
                }
                
                dispatch_main_sync_safe(^{
                    resultHandler(imageResult, info);
                });
            }];
}

- (void)cancelImageRequest:(int32_t)requestID
{
    if (kMUAssetsLibraryUnauthorized) {
        return;
    }
    if (requestID > 0 && _imageManager) {
        [_imageManager cancelImageRequest:requestID];
    }
}

- (UIImage *)imageForAsset:(MUAsset *)asset imageType:(MUAssetImageType)imageType
{
    if ([asset.realAsset isKindOfClass:[PHAsset class]]) {
        return [self imageForPHAsset:asset.realAsset imageType:imageType];
    }
    else if ([asset.realAsset isKindOfClass:[ALAsset class]]) {
        return [self imageForALAsset:asset.realAsset imageType:imageType];
    }
    return nil;
}

- (UIImage *)imageForPHAsset:(PHAsset *)asset imageType:(MUAssetImageType)imageType
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

- (UIImage *)imageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType
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
            // 超长图取原始高清图
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
            image = [image p_fixOrientation];
        }
            break;
    }
    if (image == nil && asset.aspectRatioThumbnail) {
        image = [UIImage imageWithCGImage:asset.aspectRatioThumbnail];
    }
    return image;
}

- (void)requestImageForALAsset:(ALAsset *)asset imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized) {
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

- (void)requestImageForALAssetURL:(NSURL *)assetURL imageType:(MUAssetImageType)imageType resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized || !assetURL) {
        resultHandler(nil, nil);
        return;
    }

    __weak MUAssetsLibrary *wSelf = self;
    [_assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
        [wSelf requestImageForALAsset:asset imageType:imageType resultHandler:resultHandler];
    } failureBlock:^(NSError *error) {
        resultHandler(nil, nil);
    }];
}


#pragma mark - Video Request

- (int32_t)requestVideoAVAssetForAsset:(MUAsset *)asset resultHandler:(void (^)(AVAsset *asset, NSDictionary *info))resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if (kMUAssetsLibraryUnauthorized || !asset.localIdentifier) {
        resultHandler(nil, nil);
        return 0;
    }
    
    if ([asset.realAsset isKindOfClass:[PHAsset class]]) {
        if (!asset.realAsset || ![asset.realAsset isKindOfClass:[PHAsset class]]) {
            resultHandler(nil, nil);
            return 0;
        }
        return [_imageManager requestAVAssetForVideo:asset.realAsset options:nil resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info) {
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


#pragma mark - Write Data

- (void)writeImage:(UIImage *)image completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (kMUAssetsLibraryUnauthorized) {
        return;
    }
    if (!image) {
        if (completionHandler)
            completionHandler(nil, nil);
        return;
    }
    if (kIsiOS8) {
        [self p_writeDataPerformChange:^NSString *{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
            return [request placeholderForCreatedAsset].localIdentifier;
        } completionHandler:completionHandler];
    }
    else {
        [self p_writeImageWithAssetsLibrary:image completionHandler:completionHandler];
    }
}

- (void)writeImage:(UIImage *)image metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (kMUAssetsLibraryUnauthorized || !image) {
        if (completionHandler) {
            completionHandler(nil, nil);
        }
        return;
    }
    if (!self.assetsLibrary) {
        self.assetsLibrary = [[ALAssetsLibrary alloc] init];
    }
    __weak MUAssetsLibrary *wSelf = self;
    [_assetsLibrary writeImageToSavedPhotosAlbum:image.CGImage metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error.code == ALAssetsLibraryWriteBusyError) {
            // recursive
            [wSelf writeImage:image metadata:metadata completionHandler:completionHandler];
            return;
        }
        if (!completionHandler) {
            return;
        }
        if (error || !assetURL) {
            dispatch_main_sync_safe(^{
                if (completionHandler)
                    completionHandler(nil, error);
            });
        }
        else {
            if (kIsiOS8) {
                PHFetchResult *fetchResult = [PHAsset fetchAssetsWithALAssetURLs:@[assetURL] options:nil];
                id result = nil;
                if (fetchResult.count > 0) {
                    result = [MUAsset p_assetWithPHAsset:fetchResult.firstObject];
                }
                dispatch_main_sync_safe(^{
                    if (completionHandler)
                        completionHandler(result, nil);
                });
            }
            else {
                [wSelf.assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                    if (!asset) {
                    }
                    dispatch_main_sync_safe(^{
                        if (completionHandler) {
                            completionHandler([MUAsset p_assetWithALAsset:asset], nil);
                        }
                    });
                } failureBlock:^(NSError *error) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler(nil, error);
                    });
                }];
            }
        }
    }]; 
}

- (void)writeImageData:(NSData *)imageData metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (kMUAssetsLibraryUnauthorized || !imageData) {
        if (completionHandler) {
            completionHandler(nil, nil);
        }
        return;
    }
    if (!self.assetsLibrary) {
        self.assetsLibrary = [[ALAssetsLibrary alloc] init];
    }
    __weak MUAssetsLibrary *wSelf = self;
    [_assetsLibrary writeImageDataToSavedPhotosAlbum:imageData metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error.code == ALAssetsLibraryWriteBusyError) {
            // recursive
            [wSelf writeImageData:imageData metadata:metadata completionHandler:completionHandler];
            return;
        }
        if (completionHandler) {
            if (error) {
                dispatch_main_sync_safe(^{
                    if (completionHandler)
                        completionHandler(nil, error);
                });
            }
            else {
                [wSelf.assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler) {
                            completionHandler([MUAsset p_assetWithALAsset:asset], nil);
                        }
                    });
                } failureBlock:^(NSError *error) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler(nil, error);
                    });
                }];
            }
        }
    }];
}

- (void)writeVideoAtURL:(NSURL *)url completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (kMUAssetsLibraryUnauthorized) {
        return;
    }
    if (!url) {
        completionHandler(nil, nil);
        return;
    }
    if (kIsiOS8) {
        [self p_writeDataPerformChange:^NSString *{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
            return [request placeholderForCreatedAsset].localIdentifier;
        } completionHandler:completionHandler];
    }
    else {
        [self p_writeVideoWithAssetsLibraryAtURL:url completionHandler:completionHandler];
    }
}

- (void)createAssetCollectionWithTitle:(NSString *)title completionHandler:(void(^)(MUAssetCollection *assetCollection, NSError *error))completionHandler
{
    if (kIsiOS8) {
        __block NSString *localIdentifier = nil;
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:title];
            localIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier;
        } completionHandler:^(BOOL success, NSError *error) {
            MUAssetCollection *result = nil;
            if (success && localIdentifier) {
                PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[localIdentifier] options:nil];
                if (fetchResult.count > 0) {
                    result = [MUAssetCollection p_assetCollectionWithPHAssetCollection:fetchResult.firstObject fetchOptions:nil];
                }
            }
            if (completionHandler) {
                completionHandler(result, error);
            }
            if (!success) {
                NSLog(@"*** Error creating album: %@", error);
            }
        }];
    }
    else {
        // ALAssetsLibrary创建相册如果重名会返回nil
        [_assetsLibrary addAssetsGroupAlbumWithName:title resultBlock:^(ALAssetsGroup *group) {
            if (completionHandler) {
                MUAssetCollection *result = nil;
                if (group) {
                    result = [MUAssetCollection p_assetCollectionWithAssetsGroup:group];
                }
                completionHandler(result, nil);
            }
        } failureBlock:^(NSError *error) {
            if (completionHandler) {
                completionHandler(nil, error);
            }
            NSLog(@"*** Error creating album: %@", error);
        }];
    }
}


#pragma mark - Export Video

- (void)exportVideoForAsset:(MUAsset *)asset outputURL:(NSURL *)outputURL completionHandler:(void(^)(BOOL success))completionHandler
{
    [self requestVideoAVAssetForAsset:asset resultHandler:^(AVAsset *avAsset, NSDictionary *info) {
        if (avAsset) {
            [self exportVideoForAVAsset:avAsset presetName:AVAssetExportPresetMediumQuality outputURL:outputURL maxLength:60 completionHandler:completionHandler];
        }
        else {
            dispatch_main_sync_safe(^{
                if (completionHandler) {
                    completionHandler(NO);
                }
            });
        }
    }];
}

- (void)exportVideoForAVAsset:(AVAsset *)avAsset presetName:(NSString *)presetName outputURL:(NSURL *)outputURL maxLength:(NSInteger)maxLength completionHandler:(void(^)(BOOL success))completionHandler
{
    if (kMUAssetsLibraryUnauthorized) {
        return;
    }
    AVAssetExportSession *session = [AVAssetExportSession exportSessionWithAsset:avAsset presetName:presetName];
    NSString *outputPath = [outputURL path];
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
    }
    session.outputURL = outputURL;
    session.outputFileType = AVFileTypeMPEG4;
    session.shouldOptimizeForNetworkUse = YES;
    if (maxLength == 0) {
        maxLength = 60;
    }
    session.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(600 * maxLength, 600));
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_main_sync_safe(^{
            if (completionHandler) {
                completionHandler(session.status == AVAssetExportSessionStatusCompleted);
            }
        });
    }];
}

- (void)requestAssetWithLocalIdentifier:(NSString *)localIdentifier completionHandler:(void (^)(MUAsset *asset))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized || !localIdentifier) {
        completionHandler(nil);
        return;
    }
    if ([localIdentifier hasPrefix:ALAAssetURLScheme]) {
        [self p_requestAssetWithALAAssetURL:[NSURL URLWithString:localIdentifier] completionHandler:completionHandler];
    }
    else {
        [self p_requestAssetWithPHLocalIdentifier:localIdentifier completionHandler:completionHandler];
    }
}

- (void)requestAssetWithAssetURL:(NSURL *)assetURL completionHandler:(void (^)(MUAsset *asset))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized || !assetURL) {
        completionHandler(nil);
        return;
    }
    NSString *scheme = [assetURL.scheme lowercaseString];
    if ([scheme isEqualToString:ALAAssetURLScheme]) {
        [self p_requestAssetWithALAAssetURL:assetURL completionHandler:completionHandler];
    }
    else if ([scheme isEqualToString:PHAssetURLScheme]){
        NSString *prefix = [PHAssetURLScheme stringByAppendingString:@"://"];
        NSString *localIdentifier = [assetURL.absoluteString stringByReplacingOccurrencesOfString:prefix withString:@""];
        [self p_requestAssetWithPHLocalIdentifier:localIdentifier completionHandler:completionHandler];
    }
}


#pragma mark - Metadata

- (void)requestMetadataWithAsset:(MUAsset *)asset completionHandler:(void (^)(NSDictionary *metadata))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if ([asset.realAsset isKindOfClass:[PHAsset class]]) {
        PHContentEditingInputRequestOptions *editOptions = [[PHContentEditingInputRequestOptions alloc]init];
        editOptions.networkAccessAllowed = YES;
        [asset.realAsset requestContentEditingInputWithOptions:editOptions completionHandler:^(PHContentEditingInput *contentEditingInput, NSDictionary *info) {
            CIImage *image = [CIImage imageWithContentsOfURL:contentEditingInput.fullSizeImageURL];
            dispatch_main_sync_safe(^{
                completionHandler(image.properties);
            });
        }];
    }
    else {
        completionHandler([asset.realAsset defaultRepresentation].metadata);
    }
}

#pragma mark - Image Cache

- (void)startCachingThumbnailForAssets:(NSArray *)assets
{
    [self startCachingImagesForAssets:assets imageType:MUAssetImageTypeThumbnail];
}

- (void)startCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType
{
    if (kMUAssetsLibraryUnauthorized) {
        return;
    }
    NSArray *assetArray = [self p_phAssetsForMUAssets:assets];
    if (assetArray) {
        [self.imageManager startCachingImagesForAssets:assetArray
                                            targetSize:[self p_imageTargetSizeForImageType:imageType]
                                           contentMode:(PHImageContentMode)[self p_imageContentModeForImageType:imageType]
                                               options:nil];
    }
}

- (void)stopCachingThumbnailForAssets:(NSArray *)assets
{
    [self stopCachingImagesForAssets:assets imageType:MUAssetImageTypeThumbnail];
}

- (void)stopCachingImagesForAssets:(NSArray *)assets imageType:(MUAssetImageType)imageType
{
    if (!kMUAssetsLibraryUnauthorized) {
        NSArray *assetArray = [self p_phAssetsForMUAssets:assets];
        if (assetArray) {
            [self.imageManager stopCachingImagesForAssets:assetArray
                                               targetSize:[self p_imageTargetSizeForImageType:imageType]
                                              contentMode:(PHImageContentMode)[self p_imageContentModeForImageType:imageType]
                                                  options:nil];
        }
    }
}

- (void)stopCachingImagesForAllAssets
{
    if (!kMUAssetsLibraryUnauthorized) {
        [self.imageManager stopCachingImagesForAllAssets];
    }
}


#pragma mark - Private Write

- (void)p_writeDataPerformChange:(MUAssetWritePerformChangeBlock)changeBlock completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (!changeBlock) {
        if (completionHandler)
            completionHandler(nil, nil);
        return;
    }
    __block NSString *localIdentifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        localIdentifier = changeBlock();
    } completionHandler:^(BOOL success, NSError *error) {
        if (completionHandler) {
            if (success) {
                PHFetchResult *fetch = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
                if (fetch.count > 0) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler([MUAsset p_assetWithPHAsset:[fetch firstObject]], nil);
                    });
                    return;
                }
            }
            dispatch_main_sync_safe(^{
                if (completionHandler)
                    completionHandler(nil, error);
            });
        }
    }];
}

- (void)p_writeImageWithAssetsLibrary:(UIImage *)image completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (kMUAssetsLibraryUnauthorized) {
        if (completionHandler) {
            completionHandler(nil, nil);
        }
        return;
    }
    __weak MUAssetsLibrary *wSelf = self;
    [_assetsLibrary writeImageToSavedPhotosAlbum:image.CGImage orientation:(ALAssetOrientation)image.imageOrientation completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error.code == ALAssetsLibraryWriteBusyError) {
            // recursive
            [wSelf p_writeImageWithAssetsLibrary:image completionHandler:completionHandler];
            return;
        }
        if (completionHandler) {
            if (error) {
                dispatch_main_sync_safe(^{
                    if (completionHandler)
                        completionHandler(nil, error);
                });
            }
            else {
                [wSelf.assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler([MUAsset p_assetWithALAsset:asset], nil);
                    });
                } failureBlock:^(NSError *error) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler(nil, error);
                    });
                }];
            }
        }
    }];
}

- (void)p_writeVideoWithAssetsLibraryAtURL:(NSURL *)url completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (kMUAssetsLibraryUnauthorized) {
        if (completionHandler) {
            completionHandler(nil, nil);
        }
        return;
    }
    __weak MUAssetsLibrary *wSelf = self;
    [_assetsLibrary writeVideoAtPathToSavedPhotosAlbum:url completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error.code == ALAssetsLibraryWriteBusyError) {
            // recursive
            [wSelf p_writeVideoWithAssetsLibraryAtURL:url completionHandler:completionHandler];
            return;
        }
        if (completionHandler) {
            if (error) {
                dispatch_main_sync_safe(^{
                    if (completionHandler)
                        completionHandler(nil, error);
                });
            }
            else {
                [wSelf.assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler([MUAsset p_assetWithALAsset:asset], nil);
                    });
                } failureBlock:^(NSError *error) {
                    dispatch_main_sync_safe(^{
                        if (completionHandler)
                            completionHandler(nil, error);
                    });
                }];
            }
        }
    }];
}


#pragma mark - Notification

- (void)appWillEnterForeground:(NSNotification *)notification
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self doPhotoLibraryChanged];
    });
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    dispatch_main_sync_safe(^{
        self.photoLibraryChanged = YES;
    });
}

- (void)assetsLibraryChangedNotification:(NSNotification *)notification
{
    self.photoLibraryChanged = YES;
}

- (void)doPhotoLibraryChanged
{
    if (self.photoLibraryChanged) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MUAssetsLibraryChangedNotification object:nil];
        self.photoLibraryChanged = NO;
    }
}


#pragma mark - Private

+ (NSArray *)p_fetchResultsOfAssetCollection
{
    NSMutableArray *albumArray = [NSMutableArray array];
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    PHFetchResult *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    if (smartAlbums) {
        [albumArray addObject:smartAlbums];
    }
    if (userAlbums) {
        [albumArray addObject:userAlbums];
    }
    return albumArray;
}

- (int32_t)p_requestiCloudImageForPHAsset:(PHAsset *)asset targetSize:(CGSize)targetSize contentMode:(MUImageContentMode)contentMode options:(PHImageRequestOptions *)options fixOrientation:(BOOL)fixOrientation resultHandler:(MUAssetsLibraryResultHandler)resultHandler
{
    if (!resultHandler) {
        return 0;
    }
    if (kMUAssetsLibraryUnauthorized || !asset) {
        resultHandler(nil, nil);
        return 0;
    }
    // 先获取缩略图
    [_imageManager requestImageForAsset:asset
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
    
    return [_imageManager requestImageForAsset:asset
                                    targetSize:self.fullScreenImageSize
                                   contentMode:PHImageContentModeAspectFit
                                       options:tmpOptions
                                 resultHandler:^(UIImage *result, NSDictionary *info)
            {
                BOOL isDegraded = ([[info objectForKey:PHImageResultIsDegradedKey] intValue] == 1);
                UIImage *imageResult = result;
                if (imageResult && !isDegraded && fixOrientation) {
                    imageResult = [imageResult p_fixOrientation];
                }
                dispatch_main_sync_safe(^{
                    NSLog(@"*** iCloud image %@, %@", info, NSStringFromCGSize(result.size));
                    resultHandler(imageResult, info);
                });
            }];
}

- (void)p_requestAssetWithALAAssetURL:(NSURL *)alaAssetURL completionHandler:(void (^)(MUAsset *asset))completionHandler
{
    [_assetsLibrary assetForURL:alaAssetURL resultBlock:^(ALAsset *alAsset) {
        if (completionHandler) {
            completionHandler([MUAsset p_assetWithALAsset:alAsset]);
        }
    } failureBlock:^(NSError *error) {
        if (completionHandler) {
            completionHandler(nil);
        }
    }];
}

- (void)p_requestAssetWithPHLocalIdentifier:(NSString *)phLocalIdentifier completionHandler:(void (^)(MUAsset *asset))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized || !phLocalIdentifier) {
        completionHandler(nil);
        return;
    }
    PHFetchResult *assetResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[phLocalIdentifier] options:nil];
    if (assetResult.count > 0) {
        completionHandler([MUAsset p_assetWithPHAsset:[assetResult firstObject]]);
    }
    else {
        completionHandler(nil);
    }
}

- (BOOL)p_imageSizeIsLong:(CGSize)size
{
    return (size.width > 0 && size.height / size.width > self.longImageAspectRation);
}

- (PHImageRequestOptions *)p_imageRequestOptionsWithImageType:(MUAssetImageType)imageType
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
    return options;
}

- (CGSize)p_imageTargetSizeForImageType:(MUAssetImageType)imageType phAsset:(PHAsset *)phAsset
{
    switch (imageType) {
        case MUAssetImageTypeThumbnail:
        case MUAssetImageTypeAspectRatioThumbnail:
            return self.thumbnailSize;
        case MUAssetImageTypeFullScreen:
            return self.fullScreenImageSize;
        case MUAssetImageTypeFullScreenEx: {
            // 超长图取原始高清图
            if (phAsset && [self p_imageSizeIsLong:CGSizeMake(phAsset.pixelWidth, phAsset.pixelHeight)]) {
                return PHImageManagerMaximumSize;
            }
            return self.fullScreenImageSize;
        }
        case MUAssetImageTypeExactFullScreenEx: {
            // 超长图取原始高清图
            if (phAsset && [self p_imageSizeIsLong:CGSizeMake(phAsset.pixelWidth, phAsset.pixelHeight)]) {
                return PHImageManagerMaximumSize;
            }
            // Exact时扩大size
            return CGSizeMake(self.fullScreenImageSize.width * 2, self.fullScreenImageSize.height * 2);
        }
        default:
            return PHImageManagerMaximumSize;
    }
}

- (CGSize)p_imageTargetSizeForImageType:(MUAssetImageType)imageType
{
    return [self p_imageTargetSizeForImageType:imageType phAsset:nil];
}

- (MUImageContentMode)p_imageContentModeForImageType:(MUAssetImageType)imageType
{
    if (imageType == MUAssetImageTypeThumbnail || imageType == MUAssetImageTypeAspectRatioThumbnail) {
        return MUImageContentModeAspectFill;
    }
    return MUImageContentModeAspectFit;
}

- (NSArray *)p_phAssetsForMUAssets:(NSArray *)MUAssets
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

- (PHFetchOptions *)p_assetFetchOptionsForMediaType:(MUAssetMediaType)mediaType
{
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    if (mediaType > MUAssetMediaTypeAny) {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", mediaType];
    }
    return options;
}

@end


@implementation UIImage (Private)

- (UIImage *)p_fixOrientation {
    
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

