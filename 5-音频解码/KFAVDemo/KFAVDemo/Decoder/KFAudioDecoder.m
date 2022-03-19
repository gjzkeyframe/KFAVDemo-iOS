//
//  KFAudioDecoder.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioDecoder.h"
#import <AudioToolbox/AudioToolbox.h>

// 自定义数据，用于封装音频解码回调中用到的数据。
typedef struct KFAudioUserData {
    UInt32 mChannels;
    UInt32 mDataSize;
    void *mData;
    AudioStreamPacketDescription mPacketDesc;
} KFAudioUserData;

@interface KFAudioDecoder () {
    UInt8 *_pcmBuffer; // 解码缓冲区。
}
@property (nonatomic, assign) AudioConverterRef audioDecoderInstance; // 音频解码器实例。
@property (nonatomic, assign) CMFormatDescriptionRef pcmFormat; // 音频解码参数。
@property (nonatomic, strong) dispatch_queue_t decoderQueue;
@property (nonatomic, assign) BOOL isError;
@end

@implementation KFAudioDecoder
#pragma mark - Lifecycle
- (instancetype)init {
    self = [super init];
    if (self) {
        _decoderQueue = dispatch_queue_create("com.KeyFrameKit.audioDecoder", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

- (void)dealloc {
    // 清理解码器。
    if (_audioDecoderInstance) {
        AudioConverterDispose(_audioDecoderInstance);
        _audioDecoderInstance = nil;
    }
    if (_pcmFormat) {
        CFRelease(_pcmFormat);
        _pcmFormat = NULL;
    }
    
    // 清理缓冲区。
    if (_pcmBuffer) {
        free(_pcmBuffer);
        _pcmBuffer = NULL;
    }
}

#pragma mark - Public Method
- (void)decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer || !CMSampleBufferGetDataBuffer(sampleBuffer) || self.isError) {
        return;
    }
    
    // 异步处理，防止主线程卡顿。
    __weak typeof(self) weakSelf = self;
    CFRetain(sampleBuffer);
    dispatch_async(_decoderQueue, ^{
        [weakSelf _decodeSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    });
}

#pragma mark - Private Method
- (void)_setupAudioDecoderInstanceWithInputAudioFormat:(AudioStreamBasicDescription)inputFormat error:(NSError **)error{
    if (_audioDecoderInstance != nil) {
        return;
    }
    
    // 1、设置音频解码器输出参数。其中一些参数与输入的音频数据参数一致。
    AudioStreamBasicDescription outputFormat = {0};
    outputFormat.mSampleRate = inputFormat.mSampleRate; // 输出采样率与输入一致。
    outputFormat.mFormatID = kAudioFormatLinearPCM; // 输出的 PCM 格式。
    outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    outputFormat.mChannelsPerFrame = (UInt32) inputFormat.mChannelsPerFrame; // 输出声道数与输入一致。
    outputFormat.mFramesPerPacket = 1; // 每个包的帧数。对于 PCM 这样的非压缩音频数据，设置为 1。
    outputFormat.mBitsPerChannel = 16; // 对于 PCM，表示采样位深。
    outputFormat.mBytesPerFrame = outputFormat.mChannelsPerFrame * outputFormat.mBitsPerChannel / 8; // 每帧字节数 (byte = bit / 8)。
    outputFormat.mBytesPerPacket = outputFormat.mFramesPerPacket * outputFormat.mBytesPerFrame; // 每个包的字节数。
    outputFormat.mReserved = 0; // 对齐方式，0 表示 8 字节对齐。

    // 2、基于音频输入和输出参数创建音频解码器。
    OSStatus status = AudioConverterNew(&inputFormat, &outputFormat, &_audioDecoderInstance);
    if (status != 0) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil];
    }
    
    // 3、创建编码格式信息 _pcmFormat。
    OSStatus result = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &outputFormat, 0, NULL, 0, NULL, NULL, &_pcmFormat);
    if (result != noErr) {
        *error = [NSError errorWithDomain:NSStringFromClass(self.class) code:result userInfo:nil];
        return;
    }
}

- (void)_decodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // 1、从输入数据中获取音频格式信息。
    CMAudioFormatDescriptionRef audioFormatRef = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!audioFormatRef) {
        return;
    }
    // 获取音频参数信息，AudioStreamBasicDescription 包含了音频的数据格式、声道数、采样位深、采样率等参数。
    AudioStreamBasicDescription audioFormat = *CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatRef);
    
    // 2、根据音频参数创建解码器实例。
    NSError *error = nil;
    // 第一次解码时创建解码器。
    if (!_audioDecoderInstance) {
        [self _setupAudioDecoderInstanceWithInputAudioFormat:audioFormat error:&error];
        if (error) {
            [self _callBackError:error];
            return;
        }
        if (!_audioDecoderInstance) {
            return;
        }
    }
    
    // 3、获取输入数据中的 AAC 编码数据。
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t audioLength;
    char *dataPointer = NULL;
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &audioLength, &dataPointer);
    if (audioLength == 0 || !dataPointer) {
        return;
    }
    
    // 4、创建解码回调中要用到的自定义数据。
    KFAudioUserData userData = {0};
    userData.mChannels = (UInt32) audioFormat.mChannelsPerFrame;
    userData.mDataSize = (UInt32) audioLength;
    userData.mData = (void *) dataPointer; // 绑定 AAC 编码数据。
    userData.mPacketDesc.mDataByteSize = (UInt32) audioLength;
    userData.mPacketDesc.mStartOffset = 0;
    userData.mPacketDesc.mVariableFramesInPacket = 0;

    // 5、创建解码输出数据缓冲区内存空间。
    // AAC 编码的每个包有 1024 帧。
    UInt32 pcmDataPacketSize = 1024;
    // 缓冲区长度：pcmDataPacketSize * 2(16 bit 采样深度) * 声道数量。
    UInt32 pcmBufferSize = (UInt32) (pcmDataPacketSize * 2 * audioFormat.mChannelsPerFrame);
    if (!_pcmBuffer) {
        _pcmBuffer = malloc(pcmBufferSize);
    }
    memset(_pcmBuffer, 0, pcmBufferSize);
    
    // 6、创建解码器接口对应的解码缓冲区 AudioBufferList，绑定缓冲区的内存空间。
    AudioBufferList outAudioBufferList = {0};
    outAudioBufferList.mNumberBuffers = 1;
    outAudioBufferList.mBuffers[0].mNumberChannels = (UInt32) audioFormat.mChannelsPerFrame;
    outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32) pcmBufferSize; // 设置解码缓冲区大小。
    outAudioBufferList.mBuffers[0].mData = _pcmBuffer; // 绑定缓冲区空间。

    // 7、输出数据描述。
    AudioStreamPacketDescription outputPacketDesc = {0};
    
    // 9、解码。
    OSStatus status = AudioConverterFillComplexBuffer(self.audioDecoderInstance, inputDataProcess, &userData, &pcmDataPacketSize, &outAudioBufferList, &outputPacketDesc);
    if (status != noErr) {
        [self _callBackError:[NSError errorWithDomain:NSStringFromClass(self.class) code:status userInfo:nil]];
        return;
    }
    
    if (outAudioBufferList.mBuffers[0].mDataByteSize > 0) {
        // 10、获取解码后的 PCM 数据并进行封装。
        // 把解码后的 PCM 数据先封装到 CMBlockBuffer 中。
        CMBlockBufferRef pcmBlockBuffer;
        size_t pcmBlockBufferSize = outAudioBufferList.mBuffers[0].mDataByteSize;
        char *pcmBlockBufferDataPointer = malloc(pcmBlockBufferSize);
        memcpy(pcmBlockBufferDataPointer, outAudioBufferList.mBuffers[0].mData, pcmBlockBufferSize);
        OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                              pcmBlockBufferDataPointer,
                                                              pcmBlockBufferSize,
                                                              NULL,
                                                              NULL,
                                                              0,
                                                              pcmBlockBufferSize,
                                                              0,
                                                              &pcmBlockBuffer);
        if (status != noErr) {
            return;
        }
        
        // 把 PCM 数据所在的 CMBlockBuffer 封装到 CMSampleBuffer 中。
        CMSampleBufferRef pcmSampleBuffer = NULL;
        CMSampleTimingInfo timingInfo = {CMTimeMake(1, audioFormat.mSampleRate), CMSampleBufferGetPresentationTimeStamp(sampleBuffer), kCMTimeInvalid };
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           pcmBlockBuffer,
                                           _pcmFormat,
                                           pcmDataPacketSize,
                                           1,
                                           &timingInfo,
                                           0,
                                           NULL,
                                           &pcmSampleBuffer);
        CFRelease(pcmBlockBuffer);
        
        // 11、回调解码数据。
        if (pcmSampleBuffer) {
            if (self.sampleBufferOutputCallBack) {
                self.sampleBufferOutputCallBack(pcmSampleBuffer);
            }
            CFRelease(pcmSampleBuffer);
        }
        
    }
}

- (void)_callBackError:(NSError*)error {
    self.isError = YES;
    if (error && self.errorCallBack) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.errorCallBack(error);
        });
    }
}

#pragma mark - Decoder CallBack
static OSStatus inputDataProcess(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    KFAudioUserData *userData = (KFAudioUserData *) inUserData;
    if (userData->mDataSize <= 0) {
        ioNumberDataPackets = 0;
        return -1;
    }
    
    // 设置解码输出数据格式信息。
    *outDataPacketDescription = &userData->mPacketDesc;
    (*outDataPacketDescription)[0].mStartOffset = 0;
    (*outDataPacketDescription)[0].mDataByteSize = userData->mDataSize;
    (*outDataPacketDescription)[0].mVariableFramesInPacket = 0;

    // 将待解码的数据拷贝到解码器的缓冲区的对应位置进行解码。
    ioData->mBuffers[0].mData = userData->mData;
    ioData->mBuffers[0].mDataByteSize = userData->mDataSize;
    ioData->mBuffers[0].mNumberChannels = userData->mChannels;
    
    return noErr;
}

@end
