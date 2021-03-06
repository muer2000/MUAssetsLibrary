//
//  ViewController.m
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/13.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import "ViewController.h"
#import "MUAssetsViewController.h"
#import "MUAssetsLibrary.h"
#import "MUAlbumTableViewCell.h"

@interface ViewController () <MUPhotoLibraryChangeObserver>

@property (nonatomic, strong) NSArray *albums;
@property (nonatomic, strong) MUAssetsLibrary *assetsLibrary;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[MUAssetsLibrary sharedLibrary] requestAssetCollectionsWithMediaType:MUAssetMediaTypeAny completionHandler:^(NSArray<MUAssetCollection *> *assetCollections, NSError *error) {
        if (assetCollections) {
            self.albums = assetCollections;
            [self.tableView reloadData];
        }
    }];
    
    [MUAssetsLibrary registerChangeObserver:self];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    MUAssetsViewController *assetsViewController = segue.destinationViewController;
    assetsViewController.assetsLibrary = [MUAssetsLibrary sharedLibrary];
    assetsViewController.assetCollection = self.albums[self.tableView.indexPathForSelectedRow.row];
}


#pragma mark - UITableViewDataSource, UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MUAssetCollection *album = self.albums[indexPath.row];
    MUAlbumTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AlbumCell" forIndexPath:indexPath];
    cell.albumTitleLabel.text = [NSString stringWithFormat:@"%@ (%zd)", album.title, album.numberOfAssets];
    [album requestPosterImageWithCompletionHandler:^(UIImage *image, NSDictionary *info) {
        cell.posterImageView.image = image;
    }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


#pragma mark - MUPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(id)changeInstance
{
    NSLog(@"changeInstance: %@", changeInstance);
}

@end
