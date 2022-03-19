//
//  KFAudioRenderViewController.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioRenderViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "KFAudioRender.h"
#import "KFMP4Demuxer.h"
#import "KFAudioDecoder.h"
#import "KFWeakProxy.h"

#define KFDecoderMaxCache 4096 * 5 // 解码数据缓冲区最大长度。

@interface KFAudioRenderViewController ()
@property (nonatomic, strong) KFDemuxerConfig *demuxerConfig;
@property (nonatomic, strong) KFMP4Demuxer *demuxer;
@property (nonatomic, strong) KFAudioDecoder *decoder;
@property (nonatomic, strong) KFAudioRender *audioRender;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, strong) NSMutableData *pcmDataCache; // 解码数据缓冲区。
@property (nonatomic, assign) NSInteger pcmDataCacheLength;
@property (nonatomic, strong) CADisplayLink *timer;
@end

@implementation KFAudioRenderViewController
#pragma mark - Property
- (KFDemuxerConfig *)demuxerConfig {
    if (!_demuxerConfig) {
        _demuxerConfig = [[KFDemuxerConfig alloc] init];
        _demuxerConfig.demuxerType = KFMediaAudio;
        NSString *videoPath = [[NSBundle mainBundle] pathForResource:@"input" ofType:@"mp4"];
        _demuxerConfig.asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    }
    
    return _demuxerConfig;
}

- (KFMP4Demuxer *)demuxer {
    if (!_demuxer) {
        _demuxer = [[KFMP4Demuxer alloc] initWithConfig:self.demuxerConfig];
        _demuxer.errorCallBack = ^(NSError *error) {
            NSLog(@"KFMP4Demuxer error:%zi %@", error.code, error.localizedDescription);
        };
    }
    
    return _demuxer;
}

- (KFAudioDecoder *)decoder {
    if (!_decoder) {
        __weak typeof(self) weakSelf = self;
        _decoder = [[KFAudioDecoder alloc] init];
        _decoder.errorCallBack = ^(NSError *error) {
            NSLog(@"KFAudioDecoder error:%zi %@", error.code, error.localizedDescription);
        };
        // 解码数据回调。在这里把解码后的音频 PCM 数据缓冲起来等待渲染。
        _decoder.sampleBufferOutputCallBack = ^(CMSampleBufferRef sampleBuffer) {
            if (sampleBuffer) {
                CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                size_t totolLength;
                char *dataPointer = NULL;
                CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totolLength, &dataPointer);
                if (totolLength == 0 || !dataPointer) {
                    return;
                }
                dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
                [weakSelf.pcmDataCache appendData:[NSData dataWithBytes:dataPointer length:totolLength]];
                weakSelf.pcmDataCacheLength += totolLength;
                dispatch_semaphore_signal(weakSelf.semaphore);
            }
        };
    }
    
    return _decoder;
}

- (KFAudioRender *)audioRender {
    if (!_audioRender) {
        __weak typeof(self) weakSelf = self;
        // 这里设置的音频声道数、采样位深、采样率需要跟输入源的音频参数一致。
        _audioRender = [[KFAudioRender alloc] initWithChannels:1 bitDepth:16 sampleRate:44100];
        _audioRender.errorCallBack = ^(NSError* error) {
            NSLog(@"KFAudioRender error:%zi %@", error.code, error.localizedDescription);
        };
        // 渲染输入数据回调。在这里把缓冲区的数据交给系统音频渲染单元渲染。
        _audioRender.audioBufferInputCallBack = ^(AudioBufferList * _Nonnull audioBufferList) {
            if (weakSelf.pcmDataCacheLength < audioBufferList->mBuffers[0].mDataByteSize) {
                memset(audioBufferList->mBuffers[0].mData, 0, audioBufferList->mBuffers[0].mDataByteSize);
            } else {
                dispatch_semaphore_wait(weakSelf.semaphore, DISPATCH_TIME_FOREVER);
                memcpy(audioBufferList->mBuffers[0].mData, weakSelf.pcmDataCache.bytes, audioBufferList->mBuffers[0].mDataByteSize);
                [weakSelf.pcmDataCache replaceBytesInRange:NSMakeRange(0, audioBufferList->mBuffers[0].mDataByteSize) withBytes:NULL length:0];
                weakSelf.pcmDataCacheLength -= audioBufferList->mBuffers[0].mDataByteSize;
                dispatch_semaphore_signal(weakSelf.semaphore);
            }
        };
    }
    
    return _audioRender;
}

#pragma mark - Lifecycle
- (void)viewDidLoad {
    [super viewDidLoad];
        
    _semaphore = dispatch_semaphore_create(1);
    _pcmDataCache = [[NSMutableData alloc] init];
    
    [self setupAudioSession];
    [self setupUI];
    
    // 通过一个 timer 来保证持续从文件中解封装和解码一定量的数据。
    _timer = [CADisplayLink displayLinkWithTarget:[KFWeakProxy proxyWithTarget:self] selector:@selector(timerCallBack:)];
    [_timer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [_timer setPaused:NO];
    
    [self.demuxer startReading:^(BOOL success, NSError * _Nonnull error) {
        NSLog(@"KFMP4Demuxer start:%d", success);
    }];
}

- (void)dealloc {
    
}

#pragma mark - Setup
- (void)setupUI {
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.title = @"Audio Render";
    self.view.backgroundColor = [UIColor whiteColor];
    
    
    // Navigation item.
    UIBarButtonItem *startRenderBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStylePlain target:self action:@selector(startRender)];
    UIBarButtonItem *stopRenderBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Stop" style:UIBarButtonItemStylePlain target:self action:@selector(stopRender)];
    self.navigationItem.rightBarButtonItems = @[startRenderBarButton, stopRenderBarButton];
}

#pragma mark - Action
- (void)startRender {
    [self.audioRender startPlaying];
}

- (void)stopRender {
    [self.audioRender stopPlaying];
}

#pragma mark - Utility
- (void)setupAudioSession {
    // 1、获取音频会话实例。
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    // 2、设置分类。
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        NSLog(@"AVAudioSession setCategory error");
    }
    
    // 3、激活会话。
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"AVAudioSession setActive error");
    }
}

- (void)timerCallBack:(CADisplayLink *)timer {
    // 定时从文件中解封装和解码一定量（不超过 KFDecoderMaxCache）的数据。
    if (self.pcmDataCacheLength <  KFDecoderMaxCache && self.demuxer.demuxerStatus == KFMP4DemuxerStatusRunning && self.demuxer.hasAudioSampleBuffer) {
        CMSampleBufferRef audioBuffer = [self.demuxer copyNextAudioSampleBuffer];
        if (audioBuffer) {
            [self decodeSampleBuffer:audioBuffer];
            CFRelease(audioBuffer);
        }
    }
}

- (void)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // 获取解封装后的 AAC 编码裸数据。
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t totolLength;
    char *dataPointer = NULL;
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totolLength, &dataPointer);
    if (totolLength == 0 || !dataPointer) {
        return;
    }
    
    // 目前 AudioDecoder 的解码接口实现的是单包（packet，1 packet 有 1024 帧）解码。而从 Demuxer 获取的一个 CMSampleBuffer 可能包含多个包，所以这里要拆一下包，再送给解码器。
    NSLog(@"SampleNum: %ld", CMSampleBufferGetNumSamples(sampleBuffer));
    for (NSInteger index = 0; index < CMSampleBufferGetNumSamples(sampleBuffer); index++) {
        // 1、获取一个包的数据。
        size_t sampleSize = CMSampleBufferGetSampleSize(sampleBuffer, index);
        CMSampleTimingInfo timingInfo;
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, index, &timingInfo);
        char *sampleDataPointer = malloc(sampleSize);
        memcpy(sampleDataPointer, dataPointer, sampleSize);
        
        // 2、将数据封装到 CMBlockBuffer 中。
        CMBlockBufferRef packetBlockBuffer;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                              sampleDataPointer,
                                                              sampleSize,
                                                              NULL,
                                                              NULL,
                                                              0,
                                                              sampleSize,
                                                              0,
                                                              &packetBlockBuffer);
        
        if (status == noErr) {
            // 3、将 CMBlockBuffer 封装到 CMSampleBuffer 中。
            CMSampleBufferRef packetSampleBuffer = NULL;
            const size_t sampleSizeArray[] = {sampleSize};
            status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                               packetBlockBuffer,
                                               CMSampleBufferGetFormatDescription(sampleBuffer),
                                               1,
                                               1,
                                               &timingInfo,
                                               1,
                                               sampleSizeArray,
                                               &packetSampleBuffer);
            CFRelease(packetBlockBuffer);
            
            // 4、解码这个包的数据。
            if (packetSampleBuffer) {
                [self.decoder decodeSampleBuffer:packetSampleBuffer];
                CFRelease(packetSampleBuffer);
            }
        }
        dataPointer += sampleSize;
    }
}

@end
