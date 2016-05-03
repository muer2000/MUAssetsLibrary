//
//  MUAssetsLibrary.m
//  MUAssetsLibrary
//
//  Created by Muer on 14-9-10.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import "MUAssetsLibrary.h"
#import <CoreLocation/CoreLocation.h>
#import "MUAssetImageManager.h"

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

#define kUnauthorizedError ([NSError errorWithDomain:@"Photos Access not allowed" code:2047 userInfo:nil])

@interface UIImage (MUMetadata)

- (NSData *)mu_dataWithMetadata:(NSDictionary *)metadata;

@end

@interface MUAsset (MUPrivate)

+ (instancetype)p_assetWithPHAsset:(PHAsset *)phAsset;
+ (instancetype)p_assetWithALAsset:(ALAsset *)alAsset;

@end

@interface MUAssetCollection (MUPrivate)

+ (instancetype)p_assetCollectionWithAssetsGroup:(ALAssetsGroup *)group;
+ (instancetype)p_assetCollectionWithPHAssetCollection:(PHAssetCollection *)phAssetCollection fetchOptions:(PHFetchOptions *)fetchOptions;
+ (instancetype)p_allPhotosCollectionWithTitle:(NSString *)title fetchOptions:(PHFetchOptions *)fetchOptions;

@property (nonatomic, readonly) NSInteger sortIndex;

@end

@interface MUAssetsLibrary ()

@property (nonatomic, strong) ALAssetsLibrary *assetsLibrary;

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
        _allPhotosAssetCollectionTitle = NSLocalizedString(@"所有照片", nil);
        if (!kIsiOS8) {
            _assetsLibrary = [[ALAssetsLibrary alloc] init];
        }
    }
    return self;
}


#pragma mark - fetch AssetCollections

- (void)requestAssetCollectionsWithMediaType:(MUAssetMediaType)mediaType completionHandler:(void(^)(NSArray<MUAssetCollection *> *assetCollections, NSError *error))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized) {
        completionHandler(nil, kUnauthorizedError);
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
                if ([[group valueForProperty:ALAssetsGroupPropertyType] intValue] == ALAssetsGroupSavedPhotos) {
                    cameraRollCollection = muAC;
                }
                else {
                    [assetCollections addObject:muAC];
                }
            }
        }
        else {
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
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_main_sync_safe(^{
                if (status == PHAuthorizationStatusAuthorized) {
                    [self p_requestPHAssetCollectionsWithMediaType:mediaType completionHandler:completionHandler];
                }
                else {
                    if (completionHandler) {
                        completionHandler(nil, kUnauthorizedError);
                    }
                }
            });
        }];
        return;
    }

    PHFetchOptions *assetFetchOptions = [self p_assetFetchOptionsForMediaType:mediaType];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *allAssetCollections = [MUAssetsLibrary p_allAssetCollectionWithOptions:nil];
        NSMutableArray *muAssetCollections = [NSMutableArray array];
        BOOL hasCameraRoll = NO;
        for (PHAssetCollection *itemAssetCollection in allAssetCollections) {
            // ignore video album
            if (mediaType != MUAssetMediaTypeAny && itemAssetCollection.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumVideos) {
                continue;
            }
            
            // 去掉最近删除资源集，最近删除 = 1000000201
            if (itemAssetCollection.assetCollectionType == PHAssetCollectionTypeSmartAlbum &&
                itemAssetCollection.assetCollectionSubtype > 10000) {
                continue;
            }
            
            MUAssetCollection *muAC = [MUAssetCollection p_assetCollectionWithPHAssetCollection:itemAssetCollection fetchOptions:assetFetchOptions];

            if (!hasCameraRoll && itemAssetCollection.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumUserLibrary) {
                hasCameraRoll = YES;
            }
            
            // 忽略空相册
            if (self.allowEmptyAlbums || muAC.numberOfAssets > 0) {
                [muAssetCollections addObject:muAC];
            }
        }
        
        // 没有“相机胶卷”时创建“所有照片”相册集并置顶
        if (!hasCameraRoll) {
            MUAssetCollection *allPhotosAC = [MUAssetCollection p_allPhotosCollectionWithTitle:self.allPhotosAssetCollectionTitle fetchOptions:assetFetchOptions];
            if (allPhotosAC.numberOfAssets > 0) {
                [muAssetCollections insertObject:allPhotosAC atIndex:0];
            }
        }

        NSSortDescriptor *sortDesc = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(sortIndex)) ascending:YES];
        [muAssetCollections sortUsingDescriptors:@[sortDesc]];
        
        dispatch_main_sync_safe(^{
            if (completionHandler) {
                completionHandler(muAssetCollections, nil);
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
            [MUAssetImageManager requestThumbnailForAsset:[MUAsset p_assetWithPHAsset:firstAsset] resultHandler:^(UIImage *image, NSDictionary *info) {
                completionHandler(image);
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


#pragma mark - Write image

- (void)writeImage:(UIImage *)image completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    [self writeImage:image metadata:nil completionHandler:completionHandler];
}

- (void)writeImage:(UIImage *)image metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (!image) {
        if (completionHandler) {
            completionHandler(nil, nil);
        }
        return;
    }
    if (kMUAssetsLibraryUnauthorized) {
        if (completionHandler) {
            completionHandler(nil, kUnauthorizedError);
        }
        return;
    }
    
    if (kIsiOS8) {
        if (metadata) {
            [self p_photoLibraryWriteImage:image metadata:metadata completionHandler:completionHandler];
        }
        else {
            [self p_writeAssetPerformChange:^NSString *{
                PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                return request.placeholderForCreatedAsset.localIdentifier;
            } completionHandler:completionHandler];
        }
    }
    else {
        [self p_assetsLibraryWriteImage:image metadata:metadata completionHandler:completionHandler];
    }
}

- (void)writeVideoAtURL:(NSURL *)url completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    if (!url) {
        if (completionHandler) {
            completionHandler(nil, nil);
        }
        return;
    }
    if (kMUAssetsLibraryUnauthorized) {
        if (completionHandler) {
            completionHandler(nil, kUnauthorizedError);
        }
        return;
    }
    if (kIsiOS8) {
        [self p_writeAssetPerformChange:^NSString *{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
            return request.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:completionHandler];
    }
    else {
        [self p_writeVideoWithAssetsLibraryAtURL:url completionHandler:completionHandler];
    }
}


#pragma mark - Create/Request AssetCollection

- (void)createAssetCollectionWithTitle:(NSString *)title completionHandler:(void(^)(MUAssetCollection *assetCollection, NSError *error))completionHandler
{
    if (kMUAssetsLibraryUnauthorized) {
        if (completionHandler) {
            completionHandler(nil, kUnauthorizedError);
        }
        return;
    }
    if (kIsiOS8) {
        [MUAssetsLibrary requestPhotoLibraryPermissionWithCompletionHandler:^(BOOL granted) {
            if (granted) {
                __block NSString *localIdentifier = nil;
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCollectionChangeRequest *request = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:title];
                    localIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier;
                } completionHandler:^(BOOL success, NSError *error) {
                    if (completionHandler) {
                        MUAssetCollection *result = nil;
                        if (success && localIdentifier) {
                            PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[localIdentifier] options:nil];
                            if (fetchResult.count > 0) {
                                result = [MUAssetCollection p_assetCollectionWithPHAssetCollection:fetchResult.firstObject fetchOptions:nil];
                            }
                        }
                        dispatch_main_sync_safe(^{
                            completionHandler(result, error);
                        });
                    }
                }];
            }
            else {
                if (completionHandler) {
                    completionHandler(nil, kUnauthorizedError);
                }
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

- (void)requestAssetCollectionsWithTitle:(NSString *)title completionHandler:(void (^)(MUAssetCollection *assetCollection, NSError *error))completionHandler
{
    if (!completionHandler) {
        return;
    }
    if (kMUAssetsLibraryUnauthorized) {
        completionHandler(nil, kUnauthorizedError);
        return;
    }
    
    if (kIsiOS8) {
        [MUAssetsLibrary requestPhotoLibraryPermissionWithCompletionHandler:^(BOOL granted) {
            if (granted) {
                PHFetchOptions *options = [[PHFetchOptions alloc] init];
                options.predicate = [NSPredicate predicateWithFormat:@"localizedTitle = %@", title];
                NSArray *allAssetCollections = [MUAssetsLibrary p_allAssetCollectionWithOptions:options];
                if (allAssetCollections.count > 0) {
                    completionHandler([MUAssetCollection p_assetCollectionWithPHAssetCollection:allAssetCollections.firstObject fetchOptions:nil], nil);
                }
                else {
                    completionHandler(nil, nil);
                }
            }
            else {
                completionHandler(nil, kUnauthorizedError);
            }
        }];
    }
    else {
        [_assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            if (group) {
                NSString *groupTitle = [group valueForProperty:ALAssetsGroupPropertyName];
                if ([title isEqualToString:groupTitle]) {
                    completionHandler([MUAssetCollection p_assetCollectionWithAssetsGroup:group], nil);
                    *stop = YES;
                }
            }
            else {
                completionHandler(nil, nil);
            }
        } failureBlock:^(NSError *error) {
            completionHandler(nil, error);
        }];
    }
}


#pragma mark - Request Asset

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
        PHContentEditingInputRequestOptions *editOptions = [[PHContentEditingInputRequestOptions alloc] init];
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


#pragma mark - Private Write

- (void)p_photoLibraryWriteImage:(UIImage *)image metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    NSData *imageData = [image mu_dataWithMetadata:metadata];

    // To preserve the metadata, we create an asset from the JPEG NSData representation.
    // Note that creating an asset from a UIImage discards the metadata.
    // In iOS 9, we can use -[PHAssetCreationRequest addResourceWithType:data:options].
    // In iOS 8, we save the image to a temporary file and use +[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:].
    if ([PHAssetCreationRequest class]) {
        [self p_writeAssetPerformChange:^NSString *{
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            [request addResourceWithType:PHAssetResourceTypePhoto data:imageData options:nil];
            return request.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:completionHandler];
    }
    else {
        NSString *temporaryFileName = [NSProcessInfo processInfo].globallyUniqueString;
        NSString *temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[temporaryFileName stringByAppendingPathExtension:@"jpg"]];
        NSURL *temporaryFileURL = [NSURL fileURLWithPath:temporaryFilePath];
        NSError *error = nil;
        [imageData writeToURL:temporaryFileURL options:NSDataWritingAtomic error:&error];
        if (error) {
            NSLog(@"Error occured while writing image data to a temporary file: %@", error);
            if (completionHandler) {
                completionHandler(nil, error);
            }
            return;
        }
        
        [self p_writeAssetPerformChange:^NSString *{
            PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:temporaryFileURL];
            return request.placeholderForCreatedAsset.localIdentifier;
        } completionHandler:^(MUAsset *asset, NSError *error) {
            // Delete the temporary file.
            [[NSFileManager defaultManager] removeItemAtURL:temporaryFileURL error:nil];
            if (completionHandler) {
                completionHandler(asset, error);
            }
        }];
    }
}

- (void)p_assetsLibraryWriteImage:(UIImage *)image metadata:(NSDictionary *)metadata completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    ALAssetsLibraryWriteImageCompletionBlock writeBlock = ^(NSURL *assetURL, NSError *error){
        if (error.code == ALAssetsLibraryWriteBusyError) {
            // recursive
            [self p_assetsLibraryWriteImage:image metadata:metadata completionHandler:completionHandler];
            return;
        }
        if (!completionHandler) {
            return;
        }
        if (error || !assetURL) {
            completionHandler(nil, error);
        }
        else {
            [_assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                completionHandler([MUAsset p_assetWithALAsset:asset], nil);
            } failureBlock:^(NSError *error) {
                completionHandler(nil, error);
            }];
        }
    };
    
    if (metadata) {
        [_assetsLibrary writeImageDataToSavedPhotosAlbum:UIImageJPEGRepresentation(image, 1.0)
                                                metadata:metadata
                                         completionBlock:writeBlock];
    }
    else {
        [_assetsLibrary writeImageToSavedPhotosAlbum:image.CGImage
                                         orientation:(ALAssetOrientation)image.imageOrientation
                                     completionBlock:writeBlock];
    }
}

- (void)p_writeAssetPerformChange:(MUAssetWritePerformChangeBlock)changeBlock completionHandler:(MUAssetsLibraryWriteCompletionHandler)completionHandler
{
    [MUAssetsLibrary requestPhotoLibraryPermissionWithCompletionHandler:^(BOOL granted) {
        if (granted) {
            __block NSString *localIdentifier = nil;
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                localIdentifier = changeBlock();
            } completionHandler:^(BOOL success, NSError *error) {
                if (completionHandler) {
                    MUAsset *result = nil;
                    if (success) {
                        PHFetchResult *fetch = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
                        if (fetch.count > 0) {
                            result = [MUAsset p_assetWithPHAsset:fetch.firstObject];
                        }
                    }
                    dispatch_main_sync_safe(^{
                        completionHandler(result, error);
                    });
                }
            }];
        }
        else {
            if (completionHandler) {
                completionHandler(nil, kUnauthorizedError);
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
    [_assetsLibrary writeVideoAtPathToSavedPhotosAlbum:url completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error.code == ALAssetsLibraryWriteBusyError) {
            // recursive
            [self p_writeVideoWithAssetsLibraryAtURL:url completionHandler:completionHandler];
            return;
        }
        if (completionHandler) {
            if (error) {
                completionHandler(nil, error);
            }
            else {
                [_assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                    completionHandler([MUAsset p_assetWithALAsset:asset], nil);
                } failureBlock:^(NSError *error) {
                    completionHandler(nil, error);
                }];
            }
        }
    }];
}


#pragma mark - Private

+ (NSArray *)p_allAssetCollectionWithOptions:(PHFetchOptions *)options
{
    NSMutableArray *albumArray = [NSMutableArray array];
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    [smartAlbums enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [albumArray addObject:obj];
    }];

    PHFetchResult *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    [userAlbums enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [albumArray addObject:obj];
    }];
    return albumArray;
}

- (PHFetchOptions *)p_assetFetchOptionsForMediaType:(MUAssetMediaType)mediaType
{
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    if (mediaType > MUAssetMediaTypeAny) {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", mediaType];
    }
    return options;
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


@end


#pragma mark - UIImage metadata category

@implementation UIImage (MUMetadata)

- (NSData *)mu_dataWithMetadata:(NSDictionary *)metadata
{
    NSData *imageData = UIImageJPEGRepresentation(self, 1.0);
    if (!metadata) {
        return imageData;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    
    CFStringRef UTI = CGImageSourceGetType(source);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef) data, UTI, 1, NULL);
    if (!destination) {
        NSLog(@">>> Could not create image destination <<<");
        CFRelease(source);
        return nil;
    }
    CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef) metadata);
    BOOL success = CGImageDestinationFinalize(destination);
    if (!success) {
        NSLog(@">>> Error Writing Data <<<");
    }
    CFRelease(source);
    CFRelease(destination);
    return data;
}

@end


#pragma mark - Assets library change observer

@interface MUAssetsLibraryChangeObserver : NSObject <PHPhotoLibraryChangeObserver>

@property (nonatomic, assign) BOOL photoLibraryChanged;

@end

static MUAssetsLibraryChangeObserver *kSharedLibraryChangeObserver = nil;

@implementation MUAssetsLibraryChangeObserver

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self registerLibraryChangeObserver];
    });
}

+ (void)registerLibraryChangeObserver
{
    if (!kSharedLibraryChangeObserver) {
        kSharedLibraryChangeObserver = [[MUAssetsLibraryChangeObserver alloc] init];
    }
    if (kIsiOS8) {
        [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:kSharedLibraryChangeObserver];
    }
    else {
        [[NSNotificationCenter defaultCenter] addObserver:kSharedLibraryChangeObserver selector:@selector(assetsLibraryChangedNotification:) name:ALAssetsLibraryChangedNotification object:nil];
    }
    [[NSNotificationCenter defaultCenter] addObserver:kSharedLibraryChangeObserver selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)dealloc
{
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)appWillEnterForeground:(NSNotification *)notification
{
    if (self.photoLibraryChanged) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self postPhotoLibraryChangedNotification];
        });
    }
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

- (void)postPhotoLibraryChangedNotification
{
    if (self.photoLibraryChanged) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MUAssetsLibraryChangedNotification object:nil];
        self.photoLibraryChanged = NO;
    }
}

@end