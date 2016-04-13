//
//  MUAlbumTableViewCell.h
//  MUAssetsLibraryExample
//
//  Created by Muer on 16/4/13.
//  Copyright © 2016年 Muer. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MUAlbumTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UIImageView *posterImageView;
@property (weak, nonatomic) IBOutlet UILabel *albumTitleLabel;

@end
