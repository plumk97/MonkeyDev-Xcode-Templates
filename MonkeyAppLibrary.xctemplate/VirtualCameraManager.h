//
//  VirtualCameraManager.h
//  TaimiDylib
//
//  Created by ayo on 2026/5/21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VirtualCameraManager : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

+ (instancetype)sharedInstance;
- (nullable NSURL *)mockVideoURL;
- (nullable UIImage *)mockPhotoImage;
- (nullable NSData *)mockPhotoData;
- (void)updatePreviewPlaybackTime:(CMTime)time;
- (void)startStreamingWithOutput:(AVCaptureVideoDataOutput *)output;
- (void)stopStreaming;
@property (nonatomic, weak, nullable) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;

@end

NS_ASSUME_NONNULL_END
