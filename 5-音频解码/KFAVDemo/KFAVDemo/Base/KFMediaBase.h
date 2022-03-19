//
//  KFMediaBase.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#ifndef KFMediaBase_h
#define KFMediaBase_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, KFMediaType) {
    KFMediaNone = 0,
    KFMediaAudio = 1 << 0, // 仅音频。
    KFMediaVideo = 1 << 1, // 仅视频。
    KFMediaAV = KFMediaAudio | KFMediaVideo,  // 音视频都有。
};

#endif /* KFMediaBase_h */
