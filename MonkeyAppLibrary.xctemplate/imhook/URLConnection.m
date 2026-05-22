//
//  URLConnection.m
//  imhook
//
//  Created by zhu on 2025/3/13.
//

#import "URLConnection.h"
#import "imhook.h"
#import <CaptainHook/CaptainHook.h>
#import "IMHookNetworkLog.h"

CHDeclareClass(NSURLConnection);

CHOptimizedClassMethod3(self, void, NSURLConnection, sendAsynchronousRequest, NSURLRequest *, request, queue, NSOperationQueue *, queue, completionHandler, id, handler) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    IMHookLogRequest(@"NSURLConnection sendAsynchronousRequest:queue:completionHandler:", nil, request, nil);
    
    void (^wrappedHandler)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *response, NSData *data, NSError *error) {
        IMHookLogResponse(@"NSURLConnection sendAsynchronousRequest:queue:completionHandler:", nil, response, data, error, startTime);
        if (handler) {
            ((void (^)(NSURLResponse *, NSData *, NSError *))handler)(response, data, error);
        }
    };
    
    return CHSuper3(NSURLConnection, sendAsynchronousRequest, request, queue, queue, completionHandler, wrappedHandler);
}

CHOptimizedClassMethod3(self, NSData *, NSURLConnection, sendSynchronousRequest, NSURLRequest *, request, returningResponse, NSURLResponse **, response, error, NSError **, error) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    IMHookLogRequest(@"NSURLConnection sendSynchronousRequest:returningResponse:error:", nil, request, nil);
    
    NSData *result = CHSuper3(NSURLConnection, sendSynchronousRequest, request, returningResponse, response, error, error);
    NSURLResponse *resolvedResponse = response != nil ? *response : nil;
    NSError *resolvedError = error != nil ? *error : nil;
    IMHookLogResponse(@"NSURLConnection sendSynchronousRequest:returningResponse:error:", nil, resolvedResponse, result, resolvedError, startTime);
    
    return result;
}

void hookURLConnection(void) {
    CHLoadLateClass(NSURLConnection);
    CHClassHook3(NSURLConnection, sendAsynchronousRequest, queue, completionHandler);
    CHClassHook3(NSURLConnection, sendSynchronousRequest, returningResponse, error);

}
