//
//  KFAudioConfig.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioConfig.h"

@implementation KFAudioConfig

+ (instancetype)defaultConfig {
    KFAudioConfig *config = [[self alloc] init];
    config.sampleRate = 44100;
    config.bitDepth = 16;
    config.channels = 2;

    return config;
}

@end
