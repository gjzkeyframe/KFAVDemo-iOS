//
//  KFAudioRender.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioRender.h"

#define OutputBus 0

@interface KFAudioRender ()
@property (nonatomic, assign) AudioComponentInstance audioRenderInstance; // 音频渲染实例。
@property (nonatomic, assign, readwrite) NSInteger audioChannels; // 声道数。
@property (nonatomic, assign, readwrite) NSInteger bitDepth; // 采样位深。
@property (nonatomic, assign, readwrite) NSInteger audioSampleRate; // 采样率。
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@property (nonatomic, assign) BOOL isError;
@end

@implementation KFAudioRender
#pragma mark - Lifecycle
- (instancetype)initWithChannels:(NSInteger)channels bitDepth:(NSInteger)bitDepth sampleRate:(NSInteger)sampleRate {
    self = [super init];
    if (self) {
        _audioChannels = channels;
        _bitDepth = bitDepth;
        _audioSampleRate = sampleRate;
        _renderQueue = dispatch_queue_create("com.KeyFrameKit.audioRender", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

- (void)dealloc {
    // 清理音频渲染实例。
    if (_audioRenderInstance) {
        AudioOutputUnitStop(_audioRenderInstance);
        AudioUnitUninitialize(_audioRenderInstance);
        AudioComponentInstanceDispose(_audioRenderInstance);
        _audioRenderInstance = nil;
    }
}

#pragma mark - Action
- (void)startPlaying {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_renderQueue, ^{
        if (!weakSelf.audioRenderInstance) {
            NSError *error = nil;
            // 第一次 startPlaying 时创建音频渲染实例。
            [weakSelf _setupAudioRenderInstance:&error];
            if (error) {
                // 捕捉并回调创建音频渲染实例时的错误。
                [weakSelf _callBackError:error];
                return;
            }
        }
        
        // 开始渲染。
        OSStatus status = AudioOutputUnitStart(weakSelf.audioRenderInstance);
        if (status != noErr) {
            // 捕捉并回调开始渲染时的错误。
            [weakSelf _callBackError:[NSError errorWithDomain:NSStringFromClass([KFAudioRender class]) code:status userInfo:nil]];
        }
    });
}

- (void)stopPlaying {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_renderQueue, ^{
        if (weakSelf.audioRenderInstance && !self.isError) {
            // 停止渲染。
            OSStatus status = AudioOutputUnitStop(weakSelf.audioRenderInstance);
            // 捕捉并回调停止渲染时的错误。
            if (status != noErr) {
                [weakSelf _callBackError:[NSError errorWithDomain:NSStringFromClass([KFAudioRender class]) code:status userInfo:nil]];
            }
        }
    });
}

#pragma mark - Private Method
- (void)_setupAudioRenderInstance:(NSError**)error {
    // 1、设置音频组件描述。
    AudioComponentDescription audioComponentDescription = {
        .componentType = kAudioUnitType_Output,
        //.componentSubType = kAudioUnitSubType_VoiceProcessingIO, // 回声消除模式
        .componentSubType = kAudioUnitSubType_RemoteIO,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    // 2、查找符合指定描述的音频组件。
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &audioComponentDescription);

    // 3、创建音频组件实例。
    OSStatus status = AudioComponentInstanceNew(inputComponent, &_audioRenderInstance);
    if (status != noErr) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil];
        return;
    }
    
    // 4、设置实例的属性：可读写。0 不可读写，1 可读写。
    UInt32 flag = 1;
    status = AudioUnitSetProperty(_audioRenderInstance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, OutputBus, &flag, sizeof(flag));
    if (status != noErr) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil];
        return;
    }
    
    // 5、设置实例的属性：音频参数，如：数据格式、声道数、采样位深、采样率等。
    AudioStreamBasicDescription inputFormat = {0};
    inputFormat.mFormatID = kAudioFormatLinearPCM; // 原始数据为 PCM，采用声道交错格式。
    inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    inputFormat.mChannelsPerFrame = (UInt32) self.audioChannels; // 每帧的声道数。
    inputFormat.mFramesPerPacket = 1; // 每个数据包帧数。
    inputFormat.mBitsPerChannel = (UInt32) self.bitDepth; // 采样位深。
    inputFormat.mBytesPerFrame = inputFormat.mChannelsPerFrame * inputFormat.mBitsPerChannel / 8; // 每帧字节数 (byte = bit / 8)。
    inputFormat.mBytesPerPacket = inputFormat.mFramesPerPacket * inputFormat.mBytesPerFrame; // 每个包字节数。
    inputFormat.mSampleRate = self.audioSampleRate; // 采样率
    status = AudioUnitSetProperty(_audioRenderInstance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, OutputBus, &inputFormat, sizeof(inputFormat));
    if (status != noErr) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil];
        return;
    }

    // 6、设置实例的属性：数据回调函数。
    AURenderCallbackStruct renderCallbackRef = {
        .inputProc = audioRenderCallback,
        .inputProcRefCon = (__bridge void *) (self) // 对应回调函数中的 *inRefCon。
    };
    status = AudioUnitSetProperty(_audioRenderInstance, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, OutputBus, &renderCallbackRef, sizeof(renderCallbackRef));
    if (status != noErr) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil];
        return;
    }
    
    // 7、初始化实例。
    status = AudioUnitInitialize(_audioRenderInstance);
    if (status != noErr) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil];
        return;
    }
}

- (void)_callBackError:(NSError*)error {
    self.isError = YES;
    if (self.errorCallBack) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.errorCallBack(error);
        });
    }
}

#pragma mark - Render Callback
static OSStatus audioRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    // 通过音频渲染数据输入回调从外部获取待渲染的数据。
    KFAudioRender *audioRender = (__bridge KFAudioRender *) inRefCon;
    if (audioRender.audioBufferInputCallBack) {
        audioRender.audioBufferInputCallBack(ioData);
    }
    
    return noErr;
}

@end
