//
//  KFMuxerConfig.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFMuxerConfig.h"

@implementation KFMuxerConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _muxerType = KFMediaAV;
        _preferredTransform = CGAffineTransformIdentity;
    }
    return self;
}

@end
