//
//  KFDemuxerConfig.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import "KFMediaBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface KFDemuxerConfig : NSObject
@property (nonatomic, strong) AVAsset *asset; // 待解封装的资源。
@property (nonatomic, assign) KFMediaType demuxerType; // 解封装类型。
@end

NS_ASSUME_NONNULL_END
