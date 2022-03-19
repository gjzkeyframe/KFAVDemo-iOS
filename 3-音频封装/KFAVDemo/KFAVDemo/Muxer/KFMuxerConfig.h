//
//  KFMuxerConfig.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "KFMediaBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface KFMuxerConfig : NSObject
@property (nonatomic, strong) NSURL *outputURL; // 封装文件输出地址。
@property (nonatomic, assign) KFMediaType muxerType; // 封装文件类型。
@property (nonatomic, assign) CGAffineTransform preferredTransform; // 图像的变换信息。比如：视频图像旋转。
@end

NS_ASSUME_NONNULL_END
