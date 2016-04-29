//
//  MUAssetFetchResult.h
//  MUAssetsLibrary
//
//  Created by Muer on 15/9/25.
//  Copyright © 2015年 Muer. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MUAsset;

/**
 @brief
 类似PHFetchResult功能的资源集合用来检索Asset，预先加载指定数量的资源以避免全部加载速度过慢的问题
 */
@interface MUAssetFetchResult : NSObject

- (BOOL)containsObject:(MUAsset *)anObject;

- (NSUInteger)indexOfObject:(MUAsset *)anObject;

- (MUAsset *)objectAtIndex:(NSUInteger)index;
- (MUAsset *)objectAtIndexedSubscript:(NSUInteger)idx;

- (void)enumerateObjectsUsingBlock:(void (^)(MUAsset *obj, NSUInteger idx, BOOL *stop))block;
- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(MUAsset *obj, NSUInteger idx, BOOL *stop))block;
- (void)enumerateObjectsAtIndexes:(NSIndexSet *)s options:(NSEnumerationOptions)opts usingBlock:(void (^)(MUAsset *obj, NSUInteger idx, BOOL *stop))block;

@property (nonatomic, readonly) NSUInteger count;

@property (nonatomic, readonly) MUAsset *firstObject;
@property (nonatomic, readonly) MUAsset *lastObject;

@end
