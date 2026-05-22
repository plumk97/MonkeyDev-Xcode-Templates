//
//  URLSessionTaskDelegate.m
//  imhook
//
//  Created by ayo on 2026/1/11.
//

#import "URLSessionTaskDelegate.h"
#import "IMHookNetworkLog.h"

@interface URLSessionTaskDelegateProxy ()
@property (nonatomic, strong, nullable) id originalDelegate;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableData *> *responseBodies;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSURLResponse *> *responses;
@end

@implementation URLSessionTaskDelegateProxy

- (instancetype)initWithDelegate:(id)delegate {
    self = [super init];
    if (self) {
        _originalDelegate = delegate;
        _responseBodies = [[NSMutableDictionary alloc] init];
        _responses = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [super respondsToSelector:aSelector]
        || [self.originalDelegate respondsToSelector:aSelector];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    return [super conformsToProtocol:aProtocol] || [self.originalDelegate conformsToProtocol:aProtocol];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([self.originalDelegate respondsToSelector:aSelector]) {
        return self.originalDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *signature = [super methodSignatureForSelector:aSelector];
    if (signature != nil) {
        return signature;
    }
    return [self.originalDelegate methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if (self.originalDelegate != nil) {
        [invocation invokeWithTarget:self.originalDelegate];
        return;
    }
    [super forwardInvocation:invocation];
}

- (NSMutableData *)responseBodyForTask:(NSURLSessionTask *)task createIfNeeded:(BOOL)createIfNeeded {
    if (task == nil) {
        return nil;
    }
    
    NSNumber *taskIdentifier = @(task.taskIdentifier);
    NSMutableData *body = self.responseBodies[taskIdentifier];
    if (body == nil && createIfNeeded) {
        body = [[NSMutableData alloc] init];
        self.responseBodies[taskIdentifier] = body;
    }
    return body;
}

- (void)cleanupTask:(NSURLSessionTask *)task {
    if (task == nil) {
        return;
    }
    
    NSNumber *taskIdentifier = @(task.taskIdentifier);
    [self.responseBodies removeObjectForKey:taskIdentifier];
    [self.responses removeObjectForKey:taskIdentifier];
    IMHookFinishTaskLogging(task);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if (dataTask != nil) {
        self.responses[@(dataTask.taskIdentifier)] = response;
        [self responseBodyForTask:dataTask createIfNeeded:YES];
    }
    
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
        __weak typeof(self) weakSelf = self;
        [self.originalDelegate URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition disposition) {
            if (disposition != NSURLSessionResponseAllow) {
                [weakSelf cleanupTask:dataTask];
            }
            if (completionHandler) {
                completionHandler(disposition);
            }
        }];
        return;
    }
    
    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    NSMutableData *body = [self responseBodyForTask:dataTask createIfNeeded:YES];
    [body appendData:data];
    
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)]) {
        [self.originalDelegate URLSession:session dataTask:dataTask didReceiveData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    NSNumber *taskIdentifier = @(task.taskIdentifier);
    NSURLResponse *response = self.responses[taskIdentifier] ?: task.response;
    NSData *body = [[self responseBodyForTask:task createIfNeeded:NO] copy];
    
    if (!IMHookHasLoggedResponse(task)) {
        IMHookLogResponse(@"URLSession:task:didCompleteWithError:", task, response, body, error, IMHookTaskStartTime(task));
        IMHookMarkResponseLogged(task);
    }
    
    if ([self.originalDelegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [self.originalDelegate URLSession:session task:task didCompleteWithError:error];
    }
    
    [self cleanupTask:task];
}

@end
