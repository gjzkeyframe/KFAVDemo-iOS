//
//  KFAudioDemuxerViewController.m
//  KFVideoCapture
//
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioDemuxerViewController.h"
#import "KFMP4Demuxer.h"
#import "KFAudioTools.h"

@interface KFAudioDemuxerViewController ()
@property (nonatomic, strong) KFDemuxerConfig *demuxerConfig;
@property (nonatomic, strong) KFMP4Demuxer *demuxer;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@end

@implementation KFAudioDemuxerViewController
#pragma mark - Property
- (KFDemuxerConfig *)demuxerConfig {
    if (!_demuxerConfig) {
        _demuxerConfig = [[KFDemuxerConfig alloc] init];
        // 只解封装音频。
        _demuxerConfig.demuxerType = KFMediaAudio;
        // 待解封装的资源。
        NSString *assetPath = [[NSBundle mainBundle] pathForResource:@"input" ofType:@"mp4"];
        _demuxerConfig.asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:assetPath]];
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

- (NSFileHandle *)fileHandle {
    if (!_fileHandle) {
        NSString *audioPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"output.aac"];
        [[NSFileManager defaultManager] removeItemAtPath:audioPath error:nil];
        [[NSFileManager defaultManager] createFileAtPath:audioPath contents:nil attributes:nil];
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:audioPath];
    }

    return _fileHandle;
}

#pragma mark - Lifecycle
- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupUI];
    
    // 完成音频解封装后，可以将 App Document 文件夹下面的 output.aac 文件拷贝到电脑上，使用 ffplay 播放：
    // ffplay -i output.aac
}

- (void)dealloc {
    if (_fileHandle) {
        [_fileHandle closeFile];
        _fileHandle = nil;
    }
}

#pragma mark - Setup
- (void)setupUI {
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.title = @"Audio Demuxer";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // Navigation item.
    UIBarButtonItem *startBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStylePlain target:self action:@selector(start)];
    self.navigationItem.rightBarButtonItems = @[startBarButton];
}

#pragma mark - Action
- (void)start {
    NSLog(@"KFMP4Demuxer start");
    __weak typeof(self) weakSelf = self;
    [self.demuxer startReading:^(BOOL success, NSError * _Nonnull error) {
        if (success) {
            // Demuxer 启动成功后，就可以从它里面获取解封装后的数据了。
            [weakSelf fetchAndSaveDemuxedData];
        } else {
            NSLog(@"KFMP4Demuxer error: %zi %@", error.code, error.localizedDescription);
        }
    }];
}

#pragma mark - Utility
- (void)fetchAndSaveDemuxedData {
    // 异步地从 Demuxer 获取解封装后的 AAC 编码数据。
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (self.demuxer.hasAudioSampleBuffer) {
            CMSampleBufferRef audioBuffer = [self.demuxer copyNextAudioSampleBuffer];
            if (audioBuffer) {
                [self saveSampleBuffer:audioBuffer];
                CFRelease(audioBuffer);
            }
        }
        if (self.demuxer.demuxerStatus == KFMP4DemuxerStatusCompleted) {
            NSLog(@"KFMP4Demuxer complete");
        }
    });
}

- (void)saveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // 将解封装后的数据存储为 AAC 文件。
    if (sampleBuffer) {
        // 获取解封装后的 AAC 编码裸数据。
        AudioStreamBasicDescription streamBasicDescription = *CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer));
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        size_t totolLength;
        char *dataPointer = NULL;
        CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totolLength, &dataPointer);
        if (totolLength == 0 || !dataPointer) {
            return;
        }
        
        // 将 AAC 编码裸数据存储为 AAC 文件，这时候需要在每个包前增加 ADTS 头信息。
        for (NSInteger index = 0; index < CMSampleBufferGetNumSamples(sampleBuffer); index++) {
            size_t sampleSize = CMSampleBufferGetSampleSize(sampleBuffer, index);
            [self.fileHandle writeData:[KFAudioTools adtsDataWithChannels:streamBasicDescription.mChannelsPerFrame sampleRate:streamBasicDescription.mSampleRate rawDataLength:sampleSize]];
            [self.fileHandle writeData:[NSData dataWithBytes:dataPointer length:sampleSize]];
            dataPointer += sampleSize;
        }
    }
}

@end

