//
//  HookURLProtocol.m
//  imhook
//
//  Created by ayo on 2026/1/11.
//

#import "HookURLProtocol.h"
#import "IMHookNetworkLog.h"

@implementation HookURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 拦截所有请求
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    IMHookLogRequest(@"HookURLProtocol startLoading", nil, self.request, nil);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:self.request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        IMHookLogResponse(@"HookURLProtocol startLoading", nil, response, data, error, startTime);
        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }
        
        if (response) {
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        }
        if (data) {
            [self.client URLProtocol:self didLoadData:data];
        }
        [self.client URLProtocolDidFinishLoading:self];
    }];
    [task resume];
}

- (void)stopLoading {
    // 停止任务
}


@end
