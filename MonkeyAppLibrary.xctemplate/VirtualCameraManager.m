//
//  VirtualCameraManager.m
//  TaimiDylib
//
//  Created by ayo on 2026/5/21.
//

#import "VirtualCameraManager.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VirtualCameraManager ()
@property (nonatomic, strong) AVAssetReader *assetReader;
@property (nonatomic, strong) AVAssetReaderTrackOutput *trackOutput;
@property (nonatomic, weak) AVCaptureVideoDataOutput *targetOutput;
@property (nonatomic, strong) AVAssetImageGenerator *imageGenerator;
@property (nonatomic, assign) CMTime currentMockVideoTime;
@property (nonatomic, assign) CMTime currentPreviewPlaybackTime;
@property (nonatomic, assign) CMTime cachedMockPhotoTime;
@property (nonatomic, strong) UIImage *cachedMockPhotoImage;
@property (nonatomic, strong) NSData *cachedMockPhotoData;
@end

@implementation VirtualCameraManager

+ (instancetype)sharedInstance {
    static VirtualCameraManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

- (void)resetAssetReader {
    [self.assetReader cancelReading];
    self.assetReader = nil;
    self.trackOutput = nil;
}

- (void)invalidateCachedMockPhoto {
    self.cachedMockPhotoImage = nil;
    self.cachedMockPhotoData = nil;
    self.cachedMockPhotoTime = kCMTimeInvalid;
}

// 优先从 App Bundle 读取资源，找不到时再回退到 Documents 与 tweak 自身 bundle
- (NSString *)mockVideoPath {
    NSString *videoPath = [[NSBundle mainBundle] pathForResource:@"mock_video" ofType:@"mp4"];
    if (videoPath.length > 0) {
        return videoPath;
    }

    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *documentsVideoPath = [documentsPath stringByAppendingPathComponent:@"mock_video.mp4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:documentsVideoPath]) {
        return documentsVideoPath;
    }

    NSString *classBundlePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"mock_video" ofType:@"mp4"];
    if (classBundlePath.length > 0) {
        return classBundlePath;
    }

    return nil;
}

- (NSURL *)mockVideoURL {
    NSString *videoPath = [self mockVideoPath];
    if (videoPath.length == 0) {
        return nil;
    }

    return [NSURL fileURLWithPath:videoPath];
}

- (AVAssetImageGenerator *)imageGenerator {
    if (_imageGenerator) {
        return _imageGenerator;
    }

    NSURL *videoURL = [self mockVideoURL];
    if (!videoURL) {
        return nil;
    }

    AVAsset *asset = [AVAsset assetWithURL:videoURL];
    _imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    _imageGenerator.appliesPreferredTrackTransform = YES;
    _imageGenerator.requestedTimeToleranceAfter = kCMTimeZero;
    _imageGenerator.requestedTimeToleranceBefore = kCMTimeZero;
    return _imageGenerator;
}

- (void)updateCurrentMockVideoTime:(CMTime)time {
    if (!CMTIME_IS_VALID(time)) {
        return;
    }

    if (!CMTIME_IS_VALID(self.currentMockVideoTime) || CMTimeCompare(self.currentMockVideoTime, time) != 0) {
        self.currentMockVideoTime = time;
        [self invalidateCachedMockPhoto];
    }
}

- (void)updatePreviewPlaybackTime:(CMTime)time {
    if (!CMTIME_IS_VALID(time)) {
        return;
    }

    if (!CMTIME_IS_VALID(self.currentPreviewPlaybackTime) || CMTimeCompare(self.currentPreviewPlaybackTime, time) != 0) {
        self.currentPreviewPlaybackTime = time;
        [self invalidateCachedMockPhoto];
    }
}

- (UIImage *)mockPhotoImage {
    if (self.cachedMockPhotoImage &&
        CMTIME_IS_VALID(self.cachedMockPhotoTime) &&
        ((CMTIME_IS_VALID(self.currentPreviewPlaybackTime) &&
          CMTimeCompare(self.cachedMockPhotoTime, self.currentPreviewPlaybackTime) == 0) ||
         (CMTIME_IS_VALID(self.currentMockVideoTime) &&
          CMTimeCompare(self.cachedMockPhotoTime, self.currentMockVideoTime) == 0))) {
        return self.cachedMockPhotoImage;
    }

    AVAssetImageGenerator *generator = [self imageGenerator];
    if (!generator) {
        return nil;
    }

    CMTime requestedTime = kCMTimeZero;
    if (CMTIME_IS_VALID(self.currentPreviewPlaybackTime)) {
        requestedTime = self.currentPreviewPlaybackTime;
    } else if (CMTIME_IS_VALID(self.currentMockVideoTime)) {
        requestedTime = self.currentMockVideoTime;
    }

    NSError *error = nil;
    CMTime actualTime = kCMTimeInvalid;
    CGImageRef imageRef = [generator copyCGImageAtTime:requestedTime actualTime:&actualTime error:&error];
    if (!imageRef || error) {
        NSLog(@"[VirtualCam] 错误：抽取 mock_photo 帧失败：%@", error);
        if (imageRef) {
            CGImageRelease(imageRef);
        }
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    self.cachedMockPhotoImage = image;
    self.cachedMockPhotoTime = CMTIME_IS_VALID(actualTime) ? actualTime : requestedTime;
    return image;
}

- (NSData *)mockPhotoData {
    if (self.cachedMockPhotoData) {
        return self.cachedMockPhotoData;
    }

    UIImage *image = [self mockPhotoImage];
    if (!image) {
        return nil;
    }

    NSData *data = UIImageJPEGRepresentation(image, 0.95);
    self.cachedMockPhotoData = data;
    return data;
}

- (NSDictionary *)readerOutputSettings {
    NSDictionary *videoSettings = self.targetOutput.videoSettings;
    if (videoSettings.count > 0) {
        return videoSettings;
    }

    return @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
}

// 初始化视频解码器，读取 mock_video.mp4
- (BOOL)setupAssetReader {
    NSString *videoPath = [self mockVideoPath];
    if (!videoPath) {
        NSLog(@"[VirtualCam] 错误：未在沙盒中找到 mock_video.mp4 文件！");
        return NO;
    }

    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    AVAsset *asset = [AVAsset assetWithURL:videoURL];

    NSError *error = nil;
    self.assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (!self.assetReader || error) {
        NSLog(@"[VirtualCam] 错误：创建 AVAssetReader 失败：%@", error);
        self.assetReader = nil;
        return NO;
    }

    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) {
        NSLog(@"[VirtualCam] 错误：mock_video.mp4 中没有视频轨道。");
        self.assetReader = nil;
        return NO;
    }

    NSDictionary *outputSettings = [self readerOutputSettings];
    self.trackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:outputSettings];
    if ([self.assetReader canAddOutput:self.trackOutput]) {
        [self.assetReader addOutput:self.trackOutput];
    } else {
        NSLog(@"[VirtualCam] 错误：无法将视频轨道输出添加到 AVAssetReader。");
        self.assetReader = nil;
        self.trackOutput = nil;
        return NO;
    }

    if (![self.assetReader startReading]) {
        NSLog(@"[VirtualCam] 错误：读取 mock_video.mp4 失败：%@", self.assetReader.error);
        self.assetReader = nil;
        self.trackOutput = nil;
        return NO;
    }

    NSLog(@"[VirtualCam] 已加载 mock_video.mp4：%@", videoPath);
    return YES;
}

- (void)startStreamingWithOutput:(AVCaptureVideoDataOutput *)output {
    self.targetOutput = output;
    if (!self.assetReader || self.assetReader.status != AVAssetReaderStatusReading) {
        [self resetAssetReader];
        [self setupAssetReader];
    }
}

- (CMSampleBufferRef)copyNextMockSampleBufferUsingTimingFromSampleBuffer:(CMSampleBufferRef)liveSampleBuffer CF_RETURNS_RETAINED {
    if (!self.assetReader || self.assetReader.status != AVAssetReaderStatusReading) {
        if (![self setupAssetReader]) {
            return NULL;
        }
    }

    CMSampleBufferRef mockSampleBuffer = [self.trackOutput copyNextSampleBuffer];
    if (!mockSampleBuffer) {
        NSLog(@"[VirtualCam] 视频播放完毕，正在循环重播...");
        [self resetAssetReader];
        if (![self setupAssetReader]) {
            return NULL;
        }
        mockSampleBuffer = [self.trackOutput copyNextSampleBuffer];
    }

    if (!mockSampleBuffer) {
        return NULL;
    }

    [self updateCurrentMockVideoTime:CMSampleBufferGetPresentationTimeStamp(mockSampleBuffer)];

    CMItemCount sampleCount = CMSampleBufferGetNumSamples(mockSampleBuffer);
    if (sampleCount != 1 || !liveSampleBuffer) {
        return mockSampleBuffer;
    }

    CMSampleTimingInfo timingInfo;
    OSStatus timingStatus = CMSampleBufferGetSampleTimingInfo(liveSampleBuffer, 0, &timingInfo);
    if (timingStatus != noErr) {
        return mockSampleBuffer;
    }

    CMSampleBufferRef retimedSampleBuffer = NULL;
    OSStatus status = CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
                                                            mockSampleBuffer,
                                                            1,
                                                            &timingInfo,
                                                            &retimedSampleBuffer);
    if (status != noErr || !retimedSampleBuffer) {
        return mockSampleBuffer;
    }

    CFRelease(mockSampleBuffer);
    return retimedSampleBuffer;
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = self.originalDelegate;
    if (!delegate || ![delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        return;
    }

    CMSampleBufferRef mockSampleBuffer = [self copyNextMockSampleBufferUsingTimingFromSampleBuffer:sampleBuffer];
    if (!mockSampleBuffer) {
        [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        return;
    }

    [delegate captureOutput:output didOutputSampleBuffer:mockSampleBuffer fromConnection:connection];
    CFRelease(mockSampleBuffer);
}

- (void)captureOutput:(AVCaptureOutput *)output
didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
      fromConnection:(AVCaptureConnection *)connection {
    id delegate = self.originalDelegate;
    if (delegate && [delegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) {
        [delegate captureOutput:output didDropSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
      fromConnection:(AVCaptureConnection *)connection API_AVAILABLE(ios(11.0), macos(10.13)) {
    id delegate = self.originalDelegate;
    if (delegate && [delegate respondsToSelector:@selector(captureOutput:didOutputMetadataObjects:fromConnection:)]) {
       [delegate captureOutput:output didOutputMetadataObjects:metadataObjects fromConnection:connection];
    }
}

- (void)stopStreaming {
    [self resetAssetReader];
    self.targetOutput = nil;
}

@end
