//
//  MUAsset.m
//  MUAssetsLibrary
//
//  Created by Muer on 15/9/24.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import "MUAsset.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>

NSString * const PHAssetURLScheme = @"photos-framework";
NSString * const ALAAssetURLScheme = @"assets-library";

@interface MUAsset ()

@property (nonatomic, strong) id realAsset;

@property (nonatomic, copy) NSString *localIdentifier;
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, strong) UIImage *thumbnail;
@property (nonatomic, assign) CGSize dimensions;
@property (nonatomic, strong) NSDate *creationDate;

@property (nonatomic, strong) CLLocation *location;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) MUAssetMediaType mediaType;

@end

@implementation MUAsset

- (NSString *)description
{
    return self.localIdentifier;
}


#pragma mark - Lazy load

- (NSURL *)url
{
    if (!_url) {
        if ([_realAsset isKindOfClass:[PHAsset class]]) {
            _url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@", PHAssetURLScheme, [_realAsset localIdentifier]]];
        }
        else if ([_realAsset isKindOfClass:[ALAsset class]]) {
            _url = [[_realAsset defaultRepresentation].url copy];
        }
    }
    return _url;
}

- (NSString *)localIdentifier
{
    if (!_localIdentifier) {
        if ([_realAsset isKindOfClass:[PHAsset class]]) {
            _localIdentifier = [[_realAsset localIdentifier] copy];
        }
        else if ([_realAsset isKindOfClass:[ALAsset class]]) {
            _localIdentifier = [[_realAsset defaultRepresentation].url.absoluteString copy];
        }
    }
    return _localIdentifier;
}

- (UIImage *)thumbnail
{
    if (!_thumbnail) {
        if ([_realAsset isKindOfClass:[ALAsset class]]) {
            _thumbnail = [UIImage imageWithCGImage:[(ALAsset *)_realAsset thumbnail]];
        }
        else if ([_realAsset isKindOfClass:[PHAsset class]]) {
            // nothing
        }
    }
    return _thumbnail;
}

- (CGSize)dimensions
{
    if ([_realAsset isKindOfClass:[ALAsset class]]) {
        return [[_realAsset defaultRepresentation] dimensions];
    }
    else if ([_realAsset isKindOfClass:[PHAsset class]]) {
        CGSizeMake([_realAsset pixelWidth], [_realAsset pixelHeight]);
    }
    return CGSizeZero;
}

- (NSDate *)creationDate
{
    if (!_creationDate) {
        if ([_realAsset isKindOfClass:[ALAsset class]]) {
            _creationDate = [_realAsset valueForProperty:ALAssetPropertyDate];
        }
        else if ([_realAsset isKindOfClass:[PHAsset class]]) {
            _creationDate = [(PHAsset *)_realAsset creationDate];
        }
    }
    return _creationDate;
}

- (CLLocation *)location
{
    if (!_location) {
        if ([_realAsset isKindOfClass:[ALAsset class]]) {
            _location = [_realAsset valueForProperty:ALAssetPropertyLocation];
        }
        else if ([_realAsset isKindOfClass:[PHAsset class]]) {
            _location = [(PHAsset *)_realAsset location];
        }
    }
    return _location;
}

- (NSTimeInterval)duration
{
    if ([_realAsset isKindOfClass:[ALAsset class]]) {
        return [[_realAsset valueForProperty:ALAssetPropertyDuration] doubleValue];
    }
    else if ([_realAsset isKindOfClass:[PHAsset class]]) {
        return [(PHAsset *)_realAsset duration];
    }
    return 0;
}

@end


@interface MUAsset (MUPrivate)

+ (instancetype)p_assetWithPHAsset:(PHAsset *)phAsset;
+ (instancetype)p_assetWithALAsset:(ALAsset *)alAsset;

@end

@implementation MUAsset (MUPrivate)

+ (instancetype)p_assetWithPHAsset:(PHAsset *)phAsset
{
    MUAsset *asset = [[MUAsset alloc] init];
    asset.realAsset = phAsset;
    asset.mediaType = (MUAssetMediaType)phAsset.mediaType;
    return asset;
}

+ (instancetype)p_assetWithALAsset:(ALAsset *)alAsset
{
    MUAsset *asset = [[MUAsset alloc] init];
    asset.realAsset = alAsset;
    id typeValue = [alAsset valueForProperty:ALAssetPropertyType];
    if ([typeValue isEqualToString:ALAssetTypePhoto]) {
        asset.mediaType = MUAssetMediaTypeImage;
    }
    else if ([typeValue isEqualToString:ALAssetTypeVideo]) {
        asset.mediaType = MUAssetMediaTypeVideo;
    }
    else {
        asset.mediaType = MUAssetMediaTypeUnknown;
    }
    return asset;
}

@end