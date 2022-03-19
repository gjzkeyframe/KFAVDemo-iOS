//
//  KFAudioConfig.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KFAudioConfig : NSObject
+ (instancetype)defaultConfig;

@property (nonatomic, assign) NSUInteger sampleRate; // 采样率，default: 44100。
@property (nonatomic, assign) NSUInteger bitDepth; // 量化位深，default: 16。
@property (nonatomic, assign) NSUInteger channels; // 声道数，default: 2。
@end

NS_ASSUME_NONNULL_END
