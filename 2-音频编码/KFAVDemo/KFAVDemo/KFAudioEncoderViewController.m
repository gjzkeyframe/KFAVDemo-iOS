//
//  KFAudioEncoderViewController.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioEncoderViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "KFAudioCapture.h"
#import "KFAudioEncoder.h"
#import "KFAudioTools.h"

@interface KFAudioEncoderViewController ()
@property (nonatomic, strong) KFAudioConfig *audioConfig;
@property (nonatomic, strong) KFAudioCapture *audioCapture;
@property (nonatomic, strong) KFAudioEncoder *audioEncoder;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@end

@implementation KFAudioEncoderViewController
#pragma mark - Property
- (KFAudioConfig *)audioConfig {
    if (!_audioConfig) {
        _audioConfig = [KFAudioConfig defaultConfig];
    }
    
    return _audioConfig;
}

- (KFAudioCapture *)audioCapture {
    if (!_audioCapture) {
        __weak typeof(self) weakSelf = self;
        _audioCapture = [[KFAudioCapture alloc] initWithConfig:self.audioConfig];
        _audioCapture.errorCallBack = ^(NSError* error) {
            NSLog(@"KFAudioCapture error:%zi %@", error.code, error.localizedDescription);
        };
        // 音频采集数据回调。在这里采集的 PCM 数据送给编码器。
        _audioCapture.sampleBufferOutputCallBack = ^(CMSampleBufferRef sampleBuffer) {
            [weakSelf.audioEncoder encodeSampleBuffer:sampleBuffer];
        };
    }
    
    return _audioCapture;
}

- (KFAudioEncoder *)audioEncoder {
    if (!_audioEncoder) {
        __weak typeof(self) weakSelf = self;
        _audioEncoder = [[KFAudioEncoder alloc] initWithAudioBitrate:96000];
        _audioEncoder.errorCallBack = ^(NSError* error) {
            NSLog(@"KFAudioEncoder error:%zi %@", error.code, error.localizedDescription);
        };
        // 音频编码数据回调。在这里将 AAC 数据写入文件。
        _audioEncoder.sampleBufferOutputCallBack = ^(CMSampleBufferRef sampleBuffer) {
            if (sampleBuffer) {
                // 1、获取音频编码参数信息。
                AudioStreamBasicDescription audioFormat = *CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer));
                
                // 2、获取音频编码数据。AAC 裸数据。
                CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
                size_t totolLength;
                char *dataPointer = NULL;
                CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &totolLength, &dataPointer);
                if (totolLength == 0 || !dataPointer) {
                    return;
                }
                
                // 3、在每个 AAC packet 前先写入 ADTS 头数据。
                // 由于 AAC 数据存储文件时需要在每个包（packet）前添加 ADTS 头来用于解码器解码音频流，所以这里添加一下 ADTS 头。
                [weakSelf.fileHandle writeData:[KFAudioTools adtsDataWithChannels:audioFormat.mChannelsPerFrame sampleRate:audioFormat.mSampleRate rawDataLength:totolLength]];
                
                // 4、写入 AAC packet 数据。
                [weakSelf.fileHandle writeData:[NSData dataWithBytes:dataPointer length:totolLength]];
            }
        };
    }
    
    return _audioEncoder;
}

- (NSFileHandle *)fileHandle {
    if (!_fileHandle) {
        NSString *audioPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"test.aac"];
        NSLog(@"AAC file path: %@", audioPath);
        [[NSFileManager defaultManager] removeItemAtPath:audioPath error:nil];
        [[NSFileManager defaultManager] createFileAtPath:audioPath contents:nil attributes:nil];
        _fileHandle = [NSFileHandle fileHandleForWritingAtPath:audioPath];
    }

    return _fileHandle;
}

#pragma mark - Lifecycle
- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupAudioSession];
    [self setupUI];
    
    // 完成音频编码后，可以将 App Document 文件夹下面的 test.aac 文件拷贝到电脑上，使用 ffplay 播放：
    // ffplay -i test.aac
}

- (void)dealloc {
    if (_fileHandle) {
        [_fileHandle closeFile];
    }
}

#pragma mark - Setup
- (void)setupUI {
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.title = @"Audio Encoder";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // Navigation item.
    UIBarButtonItem *startBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStylePlain target:self action:@selector(start)];
    UIBarButtonItem *stopBarButton = [[UIBarButtonItem alloc] initWithTitle:@"Stop" style:UIBarButtonItemStylePlain target:self action:@selector(stop)];
    self.navigationItem.rightBarButtonItems = @[startBarButton, stopBarButton];
}

- (void)setupAudioSession {
    NSError *error = nil;
    
    // 1、获取音频会话实例。
    AVAudioSession *session = [AVAudioSession sharedInstance];

    // 2、设置分类和选项。
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDefaultToSpeaker error:&error];
    if (error) {
        NSLog(@"AVAudioSession setCategory error.");
        error = nil;
        return;
    }
    
    // 3、设置模式。
    [session setMode:AVAudioSessionModeVideoRecording error:&error];
    if (error) {
        NSLog(@"AVAudioSession setMode error.");
        error = nil;
        return;
    }

    // 4、激活会话。
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"AVAudioSession setActive error.");
        error = nil;
        return;
    }
}

#pragma mark - Action
- (void)start {
    [self.audioCapture startRunning];
}

- (void)stop {
    [self.audioCapture stopRunning];
}

@end
