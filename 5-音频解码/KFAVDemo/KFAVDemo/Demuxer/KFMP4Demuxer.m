//
//  KFMP4Demuxer.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFMP4Demuxer.h"

#define KFMP4DemuxerBadFileError 2000
#define KFMP4DemuxerAddVideoOutputError 2001
#define KFMP4DemuxerAddAudioOutputError 2002
#define KFMP4DemuxerQueueMaxCount 3

@interface KFMP4Demuxer () {
    CMSimpleQueueRef _audioQueue;
    CMSimpleQueueRef _videoQueue;
}
@property (nonatomic, strong, readwrite) KFDemuxerConfig* config;
@property (nonatomic, strong) AVAssetReader *demuxReader; // 解封装器实例。
@property (nonatomic, strong) AVAssetReaderTrackOutput *readerAudioOutput; // Demuxer 的音频输出。
@property (nonatomic, strong) AVAssetReaderTrackOutput *readerVideoOutput; // Demuxer 的视频输出。
@property (nonatomic, strong) dispatch_queue_t demuxerQueue;
@property (nonatomic, strong) dispatch_semaphore_t demuxerSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t audioQueueSemaphore;
@property (nonatomic, strong) dispatch_semaphore_t videoQueueSemaphore;
@property (nonatomic, assign) CMTime lastAudioCopyNextTime; // 上一次拷贝的音频采样的时间戳。
@property (nonatomic, assign) CMTime lastVideoCopyNextTime; // 上一次拷贝的视频采样的时间戳。
@property (nonatomic, assign, readwrite) BOOL hasAudioTrack; // 是否包含音频数据。
@property (nonatomic, assign, readwrite) BOOL hasVideoTrack; // 是否包含视频数据。
@property (nonatomic, assign, readwrite) CGSize videoSize; // 视频大小。
@property (nonatomic, assign, readwrite) CMTime duration; // 媒体时长。
@property (nonatomic, assign, readwrite) CMVideoCodecType codecType; // 编码类型。
@property (nonatomic, assign, readwrite) KFMP4DemuxerStatus demuxerStatus; // 解封装器状态。
@property (nonatomic, assign, readwrite) BOOL audioEOF; // 是否音频结束。
@property (nonatomic, assign, readwrite) BOOL videoEOF; // 是否视频结束。
@property (nonatomic, assign, readwrite) CGAffineTransform preferredTransform; // 图像的变换信息。比如：视频图像旋转。
@end

@implementation KFMP4Demuxer
#pragma mark - LifeCycle
- (instancetype)initWithConfig:(KFDemuxerConfig *)config {
    self = [super init];
    if (self) {
        _config = config;
        _demuxerSemaphore = dispatch_semaphore_create(1);
        _audioQueueSemaphore = dispatch_semaphore_create(1);
        _videoQueueSemaphore = dispatch_semaphore_create(1);
        _demuxerStatus = KFMP4DemuxerStatusUnknown;
        _demuxerQueue = dispatch_queue_create("com.KeyFrameKit.demuxerQueue", DISPATCH_QUEUE_SERIAL);
        CMSimpleQueueCreate(kCFAllocatorDefault, KFMP4DemuxerQueueMaxCount, &_audioQueue);
        CMSimpleQueueCreate(kCFAllocatorDefault, KFMP4DemuxerQueueMaxCount, &_videoQueue);
    }
    return self;
}

- (void)dealloc {
    // 清理状态机。
    if (self.demuxerStatus == KFMP4DemuxerStatusRunning) {
        self.demuxerStatus = KFMP4DemuxerStatusCancelled;
    }
    
    // 清理解封装器实例。
    dispatch_semaphore_wait(_demuxerSemaphore, DISPATCH_TIME_FOREVER);
    if (self.demuxReader && self.demuxReader.status == AVAssetReaderStatusReading) {
        [self.demuxReader cancelReading];
    }
    dispatch_semaphore_signal(_demuxerSemaphore);
    
    // 清理音频数据队列。
    dispatch_semaphore_wait(_audioQueueSemaphore, DISPATCH_TIME_FOREVER);
    while (CMSimpleQueueGetCount(_audioQueue) > 0) {
        CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)CMSimpleQueueDequeue(_audioQueue);
        CFRelease(sampleBuffer);
    }
    dispatch_semaphore_signal(_audioQueueSemaphore);
    
    // 清理视频数据队列。
    dispatch_semaphore_wait(_videoQueueSemaphore, DISPATCH_TIME_FOREVER);
    while (CMSimpleQueueGetCount(_videoQueue) > 0) {
        CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)CMSimpleQueueDequeue(_videoQueue);
        CFRelease(sampleBuffer);
    }
    dispatch_semaphore_signal(_videoQueueSemaphore);
}

#pragma mark - Public Method
- (void)startReading:(void (^)(BOOL success, NSError *error))completeHandler {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_demuxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.demuxerSemaphore, DISPATCH_TIME_FOREVER);
        
        // 在第一次开始读数据时，创建解封装器实例。
        if (!weakSelf.demuxReader) {
            NSError *error;
            [weakSelf _setupDemuxReader:&error];
            weakSelf.audioEOF = !weakSelf.hasAudioTrack;
            weakSelf.videoEOF = !weakSelf.hasVideoTrack;
            weakSelf.demuxerStatus = error ? KFMP4DemuxerStatusFailed : KFMP4DemuxerStatusRunning;
            dispatch_semaphore_signal(weakSelf.demuxerSemaphore);
            if (completeHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completeHandler(error ? NO : YES, error);
                });
            }
            return;
        }

        dispatch_semaphore_signal(weakSelf.demuxerSemaphore);
    });
}

- (void)cancelReading {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_demuxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.demuxerSemaphore, DISPATCH_TIME_FOREVER);
        
        // 取消读数据。
        if (weakSelf.demuxReader && weakSelf.demuxReader.status == AVAssetReaderStatusReading) {
            [weakSelf.demuxReader cancelReading];
        }
        weakSelf.demuxerStatus = KFMP4DemuxerStatusCancelled;
        
        dispatch_semaphore_signal(weakSelf.demuxerSemaphore);
    });
}

- (BOOL)hasAudioSampleBuffer {
    // 是否还有音频数据。
    if (self.hasAudioTrack && self.demuxerStatus == KFMP4DemuxerStatusRunning && !self.audioEOF) {
        int32_t audioCount = 0;
        dispatch_semaphore_wait(_audioQueueSemaphore, DISPATCH_TIME_FOREVER);
        if (CMSimpleQueueGetCount(_audioQueue) > 0) {
            audioCount = CMSimpleQueueGetCount(_audioQueue);
        }
        dispatch_semaphore_signal(_audioQueueSemaphore);
        
        return (audioCount == 0 && self.audioEOF) ? NO : YES;
    }
    
    return NO;
}

- (CMSampleBufferRef)copyNextAudioSampleBuffer CF_RETURNS_RETAINED {
    // 拷贝下一份音频采样。
    CMSampleBufferRef sampleBuffer = NULL;
    while (!sampleBuffer && self.demuxerStatus == KFMP4DemuxerStatusRunning && !self.audioEOF) {
        // 先从缓冲队列取数据。
        dispatch_semaphore_wait(_audioQueueSemaphore, DISPATCH_TIME_FOREVER);
        if (CMSimpleQueueGetCount(_audioQueue) > 0) {
            sampleBuffer = (CMSampleBufferRef) CMSimpleQueueDequeue(_audioQueue);
        }
        dispatch_semaphore_signal(_audioQueueSemaphore);
        
        // 缓冲队列没有数据，就同步加载一下试试。
        if (!sampleBuffer && self.demuxerStatus == KFMP4DemuxerStatusRunning) {
            [self _syncLoadNextSampleBuffer];
        }
    }
    
    // 异步加载一下，先缓冲到数据队列中，等下次取。
    [self _asyncLoadNextSampleBuffer];
    
    return sampleBuffer;
}

- (BOOL)hasVideoSampleBuffer {
    // 是否还有视频数据。
    if (self.hasVideoTrack && self.demuxerStatus == KFMP4DemuxerStatusRunning && !self.videoEOF) {
        int32_t videoCount = 0;
        dispatch_semaphore_wait(_videoQueueSemaphore, DISPATCH_TIME_FOREVER);
        if (CMSimpleQueueGetCount(_videoQueue) > 0) {
            videoCount = CMSimpleQueueGetCount(_videoQueue);
        }
        dispatch_semaphore_signal(_videoQueueSemaphore);
        
        return (videoCount == 0 && self.videoEOF) ? NO : YES;
    }
    
    return NO;
}

- (CMSampleBufferRef)copyNextVideoSampleBuffer CF_RETURNS_RETAINED {
    // 拷贝下一份视频采样。
    CMSampleBufferRef sampleBuffer = NULL;
    while (!sampleBuffer && self.demuxerStatus == KFMP4DemuxerStatusRunning && !self.videoEOF) {
        // 先从缓冲队列取数据。
        dispatch_semaphore_wait(_videoQueueSemaphore, DISPATCH_TIME_FOREVER);
        if (CMSimpleQueueGetCount(_videoQueue) > 0) {
            sampleBuffer = (CMSampleBufferRef) CMSimpleQueueDequeue(_videoQueue);
        }
        dispatch_semaphore_signal(_videoQueueSemaphore);
        
        // 缓冲队列没有数据，就同步加载一下试试。
        if (!sampleBuffer && self.demuxerStatus == KFMP4DemuxerStatusRunning) {
            [self _syncLoadNextSampleBuffer];
        }
    }
    
    // 异步加载一下，先缓冲到数据队列中，等下次取。
    [self _asyncLoadNextSampleBuffer];
    
    return sampleBuffer;
}

#pragma mark - Private Method
- (void)_setupDemuxReader:(NSError**)error {
    if (!self.config.asset) {
        *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:40003 userInfo:nil];
        return;
    }
    
    // 1、创建解封装器实例。
    // 使用 AVAssetReader 作为解封装器。解封装的目标是 config 中的 AVAsset 资源。
    _demuxReader = [[AVAssetReader alloc] initWithAsset:self.config.asset error:error];
    if (!_demuxReader) {
        return;
    }
    
    // 2、获取时间信息。
    _duration = [self.config.asset duration];
    
    // 3、处理待解封装的资源中的视频。
    if (self.config.demuxerType & KFMediaVideo) {
        // 取出视频轨道。
        AVAssetTrack *videoTrack = [[self.config.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        _hasVideoTrack = videoTrack ? YES : NO;
        if (_hasVideoTrack) {
            // 获取图像变换信息。
            _preferredTransform = videoTrack.preferredTransform;
            
            // 获取图像大小。要应用上图像变换信息。
            _videoSize = CGSizeApplyAffineTransform(videoTrack.naturalSize, videoTrack.preferredTransform);
            _videoSize = CGSizeMake(fabs(_videoSize.width), fabs(_videoSize.height));
            
            // 获取编码格式。
            CMVideoFormatDescriptionRef formatDescription = (__bridge CMVideoFormatDescriptionRef)[[videoTrack formatDescriptions] firstObject];
            if (formatDescription) {
                _codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);
            }
            
            // 基于轨道创建视频输出。
            _readerVideoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:nil];
            _readerVideoOutput.alwaysCopiesSampleData = NO; // 避免总是做数据拷贝，影响性能。
            
            // 给解封装器绑定视频输出。
            if ([_demuxReader canAddOutput:_readerVideoOutput]) {
                [_demuxReader addOutput:_readerVideoOutput];
            } else {
                *error = _demuxReader.error ? _demuxReader.error : [NSError errorWithDomain:NSStringFromClass([self class]) code:KFMP4DemuxerAddVideoOutputError userInfo:nil];
                return;
            }
        }
    }
    
    // 4、处理待解封装的资源中的音频。
    if (self.config.demuxerType & KFMediaAudio) {
        // 取出音频轨道。
        AVAssetTrack *audioTrack = [[self.config.asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        _hasAudioTrack = audioTrack ? YES : NO;
        if (_hasAudioTrack) {
            // 基于轨道创建音频输出。
            _readerAudioOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:nil];
            _readerAudioOutput.alwaysCopiesSampleData = NO; // 避免总是做数据拷贝，影响性能。
            
            // 给解封装器绑定音频输出。
            if ([_demuxReader canAddOutput:_readerAudioOutput]) {
                [_demuxReader addOutput:_readerAudioOutput];
            } else {
                *error = _demuxReader.error ? _demuxReader.error : [NSError errorWithDomain:NSStringFromClass([self class]) code:KFMP4DemuxerAddAudioOutputError userInfo:nil];
                return;
            }
        }
    }
    
    // 5、音频和视频数据都没有，就报错。
    if (!_hasVideoTrack && !_hasAudioTrack) {
        *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:KFMP4DemuxerBadFileError userInfo:nil];
        return;
    }
    
    // 6、启动解封装。
    BOOL startSuccess = [self.demuxReader startReading];
    if (!startSuccess) {
        *error = self.demuxReader.error;
    }
}

- (void)_asyncLoadNextSampleBuffer {
    // 异步加载下一份采样数据。
    __weak typeof(self) weakSelf = self;
    dispatch_async(_demuxerQueue, ^{
        dispatch_semaphore_wait(weakSelf.demuxerSemaphore, DISPATCH_TIME_FOREVER);
        [weakSelf _loadNextSampleBuffer];
        dispatch_semaphore_signal(weakSelf.demuxerSemaphore);
    });
}

- (void)_syncLoadNextSampleBuffer {
    // 同步加载下一份采样数据。
    dispatch_semaphore_wait(self.demuxerSemaphore, DISPATCH_TIME_FOREVER);
    [self _loadNextSampleBuffer];
    dispatch_semaphore_signal(self.demuxerSemaphore);
}

- (void)_loadNextSampleBuffer {
    if (self.demuxerStatus != KFMP4DemuxerStatusRunning) {
        return;
    }
    
    // 1、根据解封装器的状态，处理异常情况。
    if (self.demuxReader.status == AVAssetReaderStatusCompleted) {
        self.demuxerStatus = KFMP4DemuxerStatusCompleted;
        return;
    } else if (self.demuxReader.status == AVAssetReaderStatusFailed) {
        if (self.demuxReader.error.code == AVErrorOperationInterrupted) {
            // 如果当前解封装器的状态是被打断而失败，就尝试重新创建一下。
            NSError *error;
            [self _setupDemuxReader:&error];
            if (!error) {
                // 同时做一下恢复处理。
                [self _resumeLastTime];
            }
        }
        
        if (self.demuxReader.status == AVAssetReaderStatusFailed) {
            // 如果状态依然是失败，就上报错误。
            self.demuxerStatus = KFMP4DemuxerStatusFailed;
            if (self.errorCallBack) {
                NSError *error = self.demuxReader.error;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.errorCallBack(error);
                });
            }
            return;
        }
    } else if (self.demuxReader.status == AVAssetReaderStatusCancelled) {
        // 如果状态是取消，就直接 return。
        self.demuxerStatus = KFMP4DemuxerStatusCancelled;
        return;
    }
    
    // 2、解封装器状态正常，加载下一份采样数据。
    BOOL audioNeedLoad = (self.config.demuxerType & KFMediaAudio) && !self.audioEOF;
    BOOL videoNeedLoad = (self.config.demuxerType & KFMediaVideo) && !self.videoEOF;
    while (self.demuxReader && self.demuxReader.status == AVAssetReaderStatusReading && (audioNeedLoad || videoNeedLoad)) {
        // 加载音频数据。
        if (audioNeedLoad) {
            dispatch_semaphore_wait(_audioQueueSemaphore, DISPATCH_TIME_FOREVER);
            int32_t audioCount = CMSimpleQueueGetCount(_audioQueue);
            dispatch_semaphore_signal(_audioQueueSemaphore);
            if (audioCount < KFMP4DemuxerQueueMaxCount) {
                // 从音频输出源读取音频数据。
                CMSampleBufferRef next = [self.readerAudioOutput copyNextSampleBuffer];
                if (next) {
                    if (!CMSampleBufferGetDataBuffer(next)) {
                        CFRelease(next);
                    } else {
                        // 将数据从音频输出源 readerAudioOutput 拷贝到缓冲队列 _audioQueue 中。
                        self.lastAudioCopyNextTime = CMSampleBufferGetPresentationTimeStamp(next);
                        dispatch_semaphore_wait(_audioQueueSemaphore, DISPATCH_TIME_FOREVER);
                        CMSimpleQueueEnqueue(_audioQueue, next);
                        audioCount = CMSimpleQueueGetCount(_audioQueue);
                        dispatch_semaphore_signal(_audioQueueSemaphore);
                    }
                } else {
                    self.audioEOF = self.demuxReader.status == AVAssetReaderStatusReading || self.demuxReader.status == AVAssetReaderStatusCompleted;
                    audioNeedLoad = NO;
                }
            } else {
                audioNeedLoad = NO;
            }
        }
        
        // 加载视频数据。
        if (videoNeedLoad) {
            dispatch_semaphore_wait(_videoQueueSemaphore, DISPATCH_TIME_FOREVER);
            int32_t videoCount = CMSimpleQueueGetCount(_videoQueue);
            dispatch_semaphore_signal(_videoQueueSemaphore);
            if (videoCount < KFMP4DemuxerQueueMaxCount) {
                // 从视频输出源读取视频数据。
                CMSampleBufferRef next = [self.readerVideoOutput copyNextSampleBuffer];
                if (next) {
                    if (!CMSampleBufferGetDataBuffer(next)) {
                        CFRelease(next);
                    } else {
                        // 将数据从视频输出源 readerVideoOutput 拷贝到缓冲队列 _videoQueue 中。
                        self.lastVideoCopyNextTime = CMSampleBufferGetDecodeTimeStamp(next);
                        dispatch_semaphore_wait(_videoQueueSemaphore, DISPATCH_TIME_FOREVER);
                        CMSimpleQueueEnqueue(_videoQueue, next);
                        videoCount = CMSimpleQueueGetCount(_videoQueue);
                        dispatch_semaphore_signal(_videoQueueSemaphore);
                    }
                } else {
                    self.videoEOF = self.demuxReader.status == AVAssetReaderStatusReading || self.demuxReader.status == AVAssetReaderStatusCompleted;
                    videoNeedLoad = NO;
                }
            } else {
                videoNeedLoad = NO;
            }
        }
    }
}

- (void)_resumeLastTime {
    // 对于异常中断后的处理，需要根据记录的时间戳 _lastAudioCopyNextTime/_lastVideoCopyNextTime 做恢复操作。
    BOOL audioNeedLoad = (_lastAudioCopyNextTime.value > 0) && !self.audioEOF;
    BOOL videoNeedLoad = (_lastVideoCopyNextTime.value > 0) && !self.videoEOF;
    while (self.demuxReader && self.demuxReader.status == AVAssetReaderStatusReading && (audioNeedLoad || videoNeedLoad)) {
        if (audioNeedLoad) {
            // 从音频输出源读取音频数据。
            CMSampleBufferRef next = [self.readerAudioOutput copyNextSampleBuffer];
            if (next) {
                if (CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(next)) <= CMTimeGetSeconds(_lastAudioCopyNextTime) || !CMSampleBufferGetDataBuffer(next)) {
                    // 从输出源取出的数据时间戳小于上次标记的时间，则表示这份采样数据已经处理过了。
                    CFRelease(next);
                } else {
                    dispatch_semaphore_wait(_audioQueueSemaphore, DISPATCH_TIME_FOREVER);
                    CMSimpleQueueEnqueue(_audioQueue, next);
                    dispatch_semaphore_signal(_audioQueueSemaphore);
                    audioNeedLoad = NO;
                }
            } else {
                self.audioEOF = self.demuxReader.status == AVAssetReaderStatusReading || self.demuxReader.status == AVAssetReaderStatusCompleted;
                audioNeedLoad = NO;
            }
        }
        
        if (videoNeedLoad) {
            // 从视频输出源读取视频数据。
            CMSampleBufferRef next = [self.readerVideoOutput copyNextSampleBuffer];
            if (next) {
                if (CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(next)) <= CMTimeGetSeconds(_lastVideoCopyNextTime) || !CMSampleBufferGetDataBuffer(next)) {
                    // 从输出源取出的数据时间戳小于上次标记的时间，则表示这份采样数据已经处理过了。
                    CFRelease(next);
                } else {
                    dispatch_semaphore_wait(_videoQueueSemaphore, DISPATCH_TIME_FOREVER);
                    CMSimpleQueueEnqueue(_videoQueue, next);
                    dispatch_semaphore_signal(_videoQueueSemaphore);
                    videoNeedLoad = NO;
                }
            } else {
                self.videoEOF = self.demuxReader.status == AVAssetReaderStatusReading || self.demuxReader.status == AVAssetReaderStatusCompleted;
                videoNeedLoad = NO;
            }
        }
    }
}

@end
