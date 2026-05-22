#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import "VirtualCameraManager.h"

static const void *kVirtualCamPreviewPlayerKey = &kVirtualCamPreviewPlayerKey;
static const void *kVirtualCamPreviewLayerKey = &kVirtualCamPreviewLayerKey;
static const void *kVirtualCamPreviewObserverKey = &kVirtualCamPreviewObserverKey;
static const void *kVirtualCamPreviewTimeObserverKey = &kVirtualCamPreviewTimeObserverKey;

static NSData *VirtualCamMockPhotoData(void) {
    return [[VirtualCameraManager sharedInstance] mockPhotoData];
}

static CGImageRef VirtualCamCopyMockPhotoCGImage(void) {
    UIImage *image = [[VirtualCameraManager sharedInstance] mockPhotoImage];
    if (!image.CGImage) {
        return nil;
    }

    return CGImageRetain(image.CGImage);
}

static void VirtualCamRemovePreviewOverlay(AVCaptureVideoPreviewLayer *previewLayer) {
    AVPlayer *player = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewPlayerKey);

    id observer = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewObserverKey);
    if (observer) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        objc_setAssociatedObject(previewLayer, kVirtualCamPreviewObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id timeObserver = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewTimeObserverKey);
    if (player && timeObserver) {
        [player removeTimeObserver:timeObserver];
        objc_setAssociatedObject(previewLayer, kVirtualCamPreviewTimeObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [player pause];
    objc_setAssociatedObject(previewLayer, kVirtualCamPreviewPlayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    AVPlayerLayer *playerLayer = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewLayerKey);
    [playerLayer removeFromSuperlayer];
    objc_setAssociatedObject(previewLayer, kVirtualCamPreviewLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void VirtualCamSyncPreviewOverlay(AVCaptureVideoPreviewLayer *previewLayer) {
    AVPlayerLayer *playerLayer = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewLayerKey);
    if (!playerLayer) {
        return;
    }

    playerLayer.frame = previewLayer.bounds;
    playerLayer.videoGravity = previewLayer.videoGravity;
    playerLayer.hidden = previewLayer.hidden;
    playerLayer.opacity = previewLayer.opacity;

    CALayer *superlayer = previewLayer.superlayer;
    if (!superlayer) {
        return;
    }

    if (playerLayer.superlayer != superlayer) {
        [superlayer addSublayer:playerLayer];
    }
    [superlayer insertSublayer:playerLayer above:previewLayer];
}

static void VirtualCamInstallPreviewOverlay(AVCaptureVideoPreviewLayer *previewLayer) {
    if (!previewLayer) {
        return;
    }

    NSURL *mockVideoURL = [[VirtualCameraManager sharedInstance] mockVideoURL];
    if (!mockVideoURL) {
        return;
    }

    AVPlayer *player = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewPlayerKey);
    AVPlayerLayer *playerLayer = objc_getAssociatedObject(previewLayer, kVirtualCamPreviewLayerKey);
    if (!player) {
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:mockVideoURL];
        player = [AVPlayer playerWithPlayerItem:item];
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                        object:item
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(__unused NSNotification *note) {
            [player seekToTime:kCMTimeZero completionHandler:^(__unused BOOL finished) {
                [[VirtualCameraManager sharedInstance] updatePreviewPlaybackTime:kCMTimeZero];
                [player play];
            }];
        }];

        id timeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30)
                                                               queue:dispatch_get_main_queue()
                                                          usingBlock:^(CMTime time) {
            [[VirtualCameraManager sharedInstance] updatePreviewPlaybackTime:time];
        }];

        playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
        playerLayer.needsDisplayOnBoundsChange = YES;

        objc_setAssociatedObject(previewLayer, kVirtualCamPreviewPlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(previewLayer, kVirtualCamPreviewLayerKey, playerLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(previewLayer, kVirtualCamPreviewObserverKey, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(previewLayer, kVirtualCamPreviewTimeObserverKey, timeObserver, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    VirtualCamSyncPreviewOverlay(previewLayer);
    [[VirtualCameraManager sharedInstance] updatePreviewPlaybackTime:player.currentTime];
    [player play];
}

// ==================== Hook 苹果系统相机 Session ====================
%hook AVCaptureSession

- (void)addInput:(AVCaptureInput *)input {
    %orig(input);
}

- (void)addOutput:(AVCaptureOutput *)output {
    %orig(output);
}

- (void)startRunning {
    %orig;
    NSLog(@"[VirtualCam] AVCaptureSession startRunning 被调用");
}

- (void)stopRunning {
    %orig;
    NSLog(@"[VirtualCam] AVCaptureSession stopRunning 被调用");
    [[VirtualCameraManager sharedInstance] stopStreaming];
}

%end

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate
                          queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (!sampleBufferDelegate) {
        [VirtualCameraManager sharedInstance].originalDelegate = nil;
        [[VirtualCameraManager sharedInstance] stopStreaming];
        %orig(sampleBufferDelegate, sampleBufferCallbackQueue);
        return;
    }

    [VirtualCameraManager sharedInstance].originalDelegate = sampleBufferDelegate;
    [[VirtualCameraManager sharedInstance] startStreamingWithOutput:self];
    NSLog(@"[VirtualCam] 已接管 AVCaptureVideoDataOutput delegate，开始注入 mock_video.mp4");
    %orig([VirtualCameraManager sharedInstance], sampleBufferCallbackQueue);
}

%end

%hook AVCaptureVideoPreviewLayer

+ (instancetype)layerWithSession:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = %orig(session);
    dispatch_async(dispatch_get_main_queue(), ^{
        VirtualCamInstallPreviewOverlay(layer);
    });
    return layer;
}

- (instancetype)initWithSession:(AVCaptureSession *)session {
    id instance = %orig(session);
    dispatch_async(dispatch_get_main_queue(), ^{
        VirtualCamInstallPreviewOverlay(instance);
    });
    return instance;
}

- (void)setSession:(AVCaptureSession *)session {
    %orig(session);

    if (session) {
        dispatch_async(dispatch_get_main_queue(), ^{
            VirtualCamInstallPreviewOverlay(self);
        });
        return;
    }

    VirtualCamRemovePreviewOverlay(self);
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);
    VirtualCamSyncPreviewOverlay(self);
}

- (void)setBounds:(CGRect)bounds {
    %orig(bounds);
    VirtualCamSyncPreviewOverlay(self);
}

- (void)setVideoGravity:(AVLayerVideoGravity)videoGravity {
    %orig(videoGravity);
    VirtualCamSyncPreviewOverlay(self);
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    VirtualCamSyncPreviewOverlay(self);
}

- (void)layoutSublayers {
    %orig;
    VirtualCamSyncPreviewOverlay(self);
}

- (void)removeFromSuperlayer {
    VirtualCamRemovePreviewOverlay(self);
    %orig;
}

%end

%hook AVCapturePhoto

- (NSData *)fileDataRepresentation {
    NSData *mockData = VirtualCamMockPhotoData();
    if (mockData.length > 0) {
        return mockData;
    }

    return %orig;
}

- (NSData *)fileDataRepresentationWithCustomizer:(id)customizer {
    NSData *mockData = VirtualCamMockPhotoData();
    if (mockData.length > 0) {
        return mockData;
    }

    return %orig(customizer);
}

- (CGImageRef)cgImageRepresentation {
    CGImageRef imageRef = VirtualCamCopyMockPhotoCGImage();
    if (imageRef) {
        return imageRef;
    }

    return %orig;
}

- (CGImageRef)previewCGImageRepresentation {
    CGImageRef imageRef = VirtualCamCopyMockPhotoCGImage();
    if (imageRef) {
        return imageRef;
    }

    return %orig;
}

%end

%hook AVCapturePhotoOutput

+ (NSData *)JPEGPhotoDataRepresentationForJPEGSampleBuffer:(CMSampleBufferRef)JPEGSampleBuffer
                                   previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer {
    NSData *mockData = VirtualCamMockPhotoData();
    if (mockData.length > 0) {
        return mockData;
    }

    return %orig(JPEGSampleBuffer, previewPhotoSampleBuffer);
}

%end
