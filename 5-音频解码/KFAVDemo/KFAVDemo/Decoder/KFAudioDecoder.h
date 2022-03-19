//
//  KFAudioDecoder.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

@interface KFAudioDecoder : NSObject
@property (nonatomic, copy) void (^sampleBufferOutputCallBack)(CMSampleBufferRef sample); // 解码器数据回调。
@property (nonatomic, copy) void (^errorCallBack)(NSError *error); // 解码器错误回调。

- (void)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer; // 解码。
@end

NS_ASSUME_NONNULL_END
