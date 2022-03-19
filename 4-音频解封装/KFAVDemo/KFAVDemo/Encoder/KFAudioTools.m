//
//  KFAudioTools.m
//  KFAVDemo
//  微信搜索『gzjkeyframe』关注公众号『关键帧Keyframe』获得最新音视频技术文章和进群交流。
//  Created by [公众号：关键帧Keyframe].
//

#import "KFAudioTools.h"

@implementation KFAudioTools

// 按音频参数生产 AAC packet 对应的 ADTS 头数据。
// 当编码器编码的是 AAC 裸流数据时，需要在每个 AAC packet 前添加一个 ADTS 头用于解码器解码音频流。
// 参考文档：
// ADTS 格式参考：http://wiki.multimedia.cx/index.php?title=ADTS
// MPEG-4 Audio 格式参考：http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
+ (NSData *)adtsDataWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate rawDataLength:(NSInteger)rawDataLength {
    // 1、创建数据缓冲区。
    int adtsLength = 7; // ADTS 头固定 7 字节。
    char *packet = malloc(sizeof(char) * adtsLength);
    
    // 2、设置各数据字段。
    int profile = 2; // 2 表示 AAC LC。
    NSInteger sampleRateIndex = [self.class sampleRateIndex:sampleRate]; // 取得采样率对应的 index。
    int channelCfg = (int) channels; // MPEG-4 Audio Channel Configuration。
    NSUInteger fullLength = adtsLength + rawDataLength; // 这里的长度字段是：ADTS 头数据和 AAC packet 数据的总长度。
    
    //  3、填充 ADTS 数据。
    packet[0] = (char) 0xFF; // 11111111     = syncword
    packet[1] = (char) 0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char) (((profile - 1) << 6) + (sampleRateIndex << 2) + (channelCfg >> 2));
    packet[3] = (char) (((channelCfg & 3) << 6) + (fullLength >> 11));
    packet[4] = (char) ((fullLength & 0x7FF) >> 3);
    packet[5] = (char) (((fullLength & 7) << 5) + 0x1F);
    packet[6] = (char) 0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    
    return data;
}

// 音频采样率对应的 index。
+ (NSInteger)sampleRateIndex:(NSInteger)frequencyInHz {
    NSInteger sampleRateIndex = 0;
    switch (frequencyInHz) {
        case 96000:
            sampleRateIndex = 0;
            break;
        case 88200:
            sampleRateIndex = 1;
            break;
        case 64000:
            sampleRateIndex = 2;
            break;
        case 48000:
            sampleRateIndex = 3;
            break;
        case 44100:
            sampleRateIndex = 4;
            break;
        case 32000:
            sampleRateIndex = 5;
            break;
        case 24000:
            sampleRateIndex = 6;
            break;
        case 22050:
            sampleRateIndex = 7;
            break;
        case 16000:
            sampleRateIndex = 8;
            break;
        case 12000:
            sampleRateIndex = 9;
            break;
        case 11025:
            sampleRateIndex = 10;
            break;
        case 8000:
            sampleRateIndex = 11;
            break;
        case 7350:
            sampleRateIndex = 12;
            break;
        default:
            sampleRateIndex = 15;
    }
    
    return sampleRateIndex;
}

@end
