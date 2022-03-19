//
//  KFWeakProxy.h
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import <Foundation/Foundation.h>

@interface KFWeakProxy : NSProxy
- (instancetype)initWithTarget:(id)target;
+ (instancetype)proxyWithTarget:(id)target;
@property (nonatomic, weak, readonly) id target;
@end
