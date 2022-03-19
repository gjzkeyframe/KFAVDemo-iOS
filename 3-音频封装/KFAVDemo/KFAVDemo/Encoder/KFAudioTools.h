//
//  KFAudioTools.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KFAudioTools : NSObject

// 按音频参数生成 AAC packet 对应的 ADTS 头数据。
+ (NSData *)adtsDataWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate rawDataLength:(NSInteger)rawDataLength;

@end

NS_ASSUME_NONNULL_END
