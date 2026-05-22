//
//  URLSessionTaskDelegate.h
//  imhook
//
//  Created by ayo on 2026/1/11.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface URLSessionTaskDelegateProxy : NSObject <NSURLSessionDataDelegate>

- (instancetype)initWithDelegate:(nullable id)delegate;

@end
NS_ASSUME_NONNULL_END
