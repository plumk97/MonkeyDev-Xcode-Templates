//
//  URLSessionHook.m
//  imhook
//
//  Created by zhu on 2025/1/16.
//

#import "URLSessionHook.h"
#import "imhook.h"
#import <CaptainHook/CaptainHook.h>
#import "IMHookNetworkLog.h"

typedef void(^NSURLSessionCompletionHandler)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error);

CHDeclareClass(NSURLSession);
CHDeclareClass(NSURLSessionConfiguration);

static NSString * const kIMHookSOCKSEnableKey = @"SOCKSEnable";
static NSString * const kIMHookSOCKSProxyKey = @"SOCKSProxy";
static NSString * const kIMHookSOCKSPortKey = @"SOCKSPort";
static NSString *kIMHookSOCKSHost = nil;
static NSNumber *kIMHookSOCKSPort = nil;

static inline NSDictionary *IMHookSOCKSProxyDictionary(void) {
    if (kIMHookSOCKSHost.length == 0 || kIMHookSOCKSPort == nil) {
        return nil;
    }
    
    return @{
        kIMHookSOCKSEnableKey: @YES,
        kIMHookSOCKSProxyKey: kIMHookSOCKSHost,
        kIMHookSOCKSPortKey: kIMHookSOCKSPort
    };
}

static inline NSURLSessionConfiguration *IMHookApplySOCKSProxy(NSURLSessionConfiguration *configuration) {
    if (configuration == nil) {
        return nil;
    }
    
    NSDictionary *proxyConfig = IMHookSOCKSProxyDictionary();
    if (proxyConfig == nil) {
        return configuration;
    }
    
    NSMutableDictionary *proxyDictionary = [NSMutableDictionary dictionaryWithDictionary:configuration.connectionProxyDictionary ?: @{}];
    [proxyDictionary addEntriesFromDictionary:proxyConfig];
    configuration.connectionProxyDictionary = proxyDictionary;
    return configuration;
}

void IMHookConfigureSOCKSProxy(NSString * _Nullable host, NSNumber * _Nullable port) {
    NSString *trimmedHost = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedHost.length == 0 || port == nil || port.integerValue <= 0) {
        kIMHookSOCKSHost = nil;
        kIMHookSOCKSPort = nil;
        NSLog(@"SOCKS5 disabled");
        return;
    }
    
    kIMHookSOCKSHost = [trimmedHost copy];
    kIMHookSOCKSPort = port;
    NSLog(@"SOCKS5 enabled %@:%@", kIMHookSOCKSHost, kIMHookSOCKSPort);
}

CHOptimizedClassMethod0(self, NSURLSessionConfiguration *, NSURLSessionConfiguration, defaultSessionConfiguration) {
    NSURLSessionConfiguration *configuration = CHSuper0(NSURLSessionConfiguration, defaultSessionConfiguration);
    return IMHookApplySOCKSProxy(configuration);
}

CHOptimizedClassMethod0(self, NSURLSessionConfiguration *, NSURLSessionConfiguration, ephemeralSessionConfiguration) {
    NSURLSessionConfiguration *configuration = CHSuper0(NSURLSessionConfiguration, ephemeralSessionConfiguration);
    return IMHookApplySOCKSProxy(configuration);
}

CHOptimizedClassMethod1(self, NSURLSessionConfiguration *, NSURLSessionConfiguration,
                        backgroundSessionConfigurationWithIdentifier, NSString *, identifier) {
    NSURLSessionConfiguration *configuration = CHSuper1(NSURLSessionConfiguration, backgroundSessionConfigurationWithIdentifier, identifier);
    return IMHookApplySOCKSProxy(configuration);
}

CHOptimizedClassMethod1(self, NSURLSession *, NSURLSession,
                        sessionWithConfiguration, NSURLSessionConfiguration *, configuration) {
    return CHSuper1(NSURLSession, sessionWithConfiguration, IMHookApplySOCKSProxy(configuration));
}

CHOptimizedClassMethod3(self, NSURLSession *, NSURLSession,
                        sessionWithConfiguration, NSURLSessionConfiguration *, configuration,
                        delegate, id, delegate,
                        delegateQueue, NSOperationQueue *, queue) {
    return CHSuper3(NSURLSession,
                    sessionWithConfiguration, IMHookApplySOCKSProxy(configuration),
                    delegate, delegate,
                    delegateQueue, queue);
}

CHOptimizedMethod3(self, NSURLSession *, NSURLSession,
                   initWithConfiguration, NSURLSessionConfiguration *, configuration,
                   delegate, id, delegate,
                   delegateQueue, NSOperationQueue *, queue) {
    return CHSuper3(NSURLSession,
                    initWithConfiguration, IMHookApplySOCKSProxy(configuration),
                    delegate, delegate,
                    delegateQueue, queue);
}

CHOptimizedMethod1(self, NSURLSessionDataTask *, NSURLSession, dataTaskWithRequest, NSURLRequest *, request) {
    
    NSURLSessionDataTask *dataTask = CHSuper1(NSURLSession, dataTaskWithRequest, request);
    IMHookPrepareTaskForLogging(dataTask);
    IMHookLogRequest(@"dataTaskWithRequest:", dataTask, request, nil);
    return dataTask;
}


CHOptimizedMethod1(self, NSURLSessionDataTask *, NSURLSession, dataTaskWithURL, NSURL *, url) {
    NSURLSessionDataTask *dataTask = CHSuper1(NSURLSession, dataTaskWithURL, url);
    NSURLRequest *request = dataTask.currentRequest;
    IMHookPrepareTaskForLogging(dataTask);
    IMHookLogRequest(@"dataTaskWithURL:", dataTask, request, nil);
    return dataTask;
}

CHOptimizedMethod2(self, NSURLSessionDataTask *, NSURLSession, dataTaskWithRequest, NSURLRequest *, request, completionHandler, NSURLSessionCompletionHandler, completionHandler) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    __block NSURLSessionDataTask *dataTask = nil;
    
    void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!IMHookHasLoggedResponse(dataTask)) {
            IMHookLogResponse(@"dataTaskWithRequest:completionHandler:", dataTask, response, data, error, startTime);
            IMHookMarkResponseLogged(dataTask);
        }
        IMHookFinishTaskLogging(dataTask);
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    dataTask = CHSuper2(NSURLSession, dataTaskWithRequest, request, completionHandler, newCompletionHandler);
    IMHookPrepareTaskForLogging(dataTask);
    IMHookLogRequest(@"dataTaskWithRequest:completionHandler:", dataTask, dataTask.currentRequest ?: request, nil);
    return dataTask;
}


CHOptimizedMethod2(self, NSURLSessionDataTask *, NSURLSession, dataTaskWithURL, NSURL *, url, completionHandler, id, completionHandler) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    __block NSURLSessionDataTask *dataTask = nil;
    
    void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!IMHookHasLoggedResponse(dataTask)) {
            IMHookLogResponse(@"dataTaskWithURL:completionHandler:", dataTask, response, data, error, startTime);
            IMHookMarkResponseLogged(dataTask);
        }
        IMHookFinishTaskLogging(dataTask);
        if (completionHandler) {
            ((void (^)(NSData *, NSURLResponse *, NSError *))completionHandler)(data, response, error);
        }
    };

    dataTask = CHSuper2(NSURLSession, dataTaskWithURL, url, completionHandler, newCompletionHandler);
    
    NSURLRequest *request = dataTask.currentRequest;
    IMHookPrepareTaskForLogging(dataTask);
    IMHookLogRequest(@"dataTaskWithURL:completionHandler:", dataTask, request, nil);
    return dataTask;
}


// MARK: - 上传相关
// (1) uploadTaskWithRequest:fromData:
CHOptimizedMethod2(self, NSURLSessionUploadTask *, NSURLSession,
                  uploadTaskWithRequest, NSURLRequest *, request,
                  fromData, NSData *, bodyData) {
    NSURLSessionUploadTask *uploadTask = CHSuper2(NSURLSession, uploadTaskWithRequest, request, fromData, bodyData);
    IMHookPrepareTaskForLogging(uploadTask);
    IMHookLogRequest(@"uploadTaskWithRequest:fromData:", uploadTask, request, bodyData);
    return uploadTask;
}

// (2) uploadTaskWithRequest:fromFile:
CHOptimizedMethod2(self, NSURLSessionUploadTask *, NSURLSession,
                  uploadTaskWithRequest, NSURLRequest *, request,
                  fromFile, NSURL *, fileURL) {
    NSURLSessionUploadTask *uploadTask = CHSuper2(NSURLSession, uploadTaskWithRequest, request, fromFile, fileURL);
    
    NSData *bodyData = nil;
    if (fileURL) {
        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        if (fileSize && fileSize.unsignedLongLongValue <= 1024 * 30) {
            bodyData = [NSData dataWithContentsOfURL:fileURL];
        }
    }
    
    IMHookPrepareTaskForLogging(uploadTask);
    IMHookLogRequest(@"uploadTaskWithRequest:fromFile:", uploadTask, request, bodyData);
    if (fileURL != nil && bodyData == nil) {
        NSLog(@"Upload Body: <file body not previewed>");
    }
    return uploadTask;
}

// (3) uploadTaskWithRequest:fromData:completionHandler:
CHOptimizedMethod3(self, NSURLSessionUploadTask *, NSURLSession,
                  uploadTaskWithRequest, NSURLRequest *, request,
                  fromData, NSData *, bodyData,
                    completionHandler, NSURLSessionCompletionHandler, completionHandler) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    __block NSURLSessionUploadTask *uploadTask = nil;
    
    void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!IMHookHasLoggedResponse(uploadTask)) {
            IMHookLogResponse(@"uploadTaskWithRequest:fromData:completionHandler:", uploadTask, response, data, error, startTime);
            IMHookMarkResponseLogged(uploadTask);
        }
        IMHookFinishTaskLogging(uploadTask);
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    uploadTask = CHSuper3(NSURLSession, uploadTaskWithRequest, request, fromData, bodyData, completionHandler, newCompletionHandler);
    IMHookPrepareTaskForLogging(uploadTask);
    IMHookLogRequest(@"uploadTaskWithRequest:fromData:completionHandler:", uploadTask, request, bodyData);
    return uploadTask;
}

// (4) uploadTaskWithRequest:fromFile:completionHandler:
CHOptimizedMethod3(self, NSURLSessionUploadTask *, NSURLSession,
                  uploadTaskWithRequest, NSURLRequest *, request,
                  fromFile, NSURL *, fileURL,
                  completionHandler, NSURLSessionCompletionHandler, completionHandler) {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    __block NSURLSessionUploadTask *uploadTask = nil;
    
    void (^newCompletionHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!IMHookHasLoggedResponse(uploadTask)) {
            IMHookLogResponse(@"uploadTaskWithRequest:fromFile:completionHandler:", uploadTask, response, data, error, startTime);
            IMHookMarkResponseLogged(uploadTask);
        }
        IMHookFinishTaskLogging(uploadTask);
        if (completionHandler) {
            completionHandler(data, response, error);
        }
    };
    
    NSData *bodyData = nil;
    if (fileURL) {
        NSNumber *fileSize = nil;
        [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
        if (fileSize && fileSize.unsignedLongLongValue <= 1024 * 30) {
            bodyData = [NSData dataWithContentsOfURL:fileURL];
        }
    }
    
    uploadTask = CHSuper3(NSURLSession, uploadTaskWithRequest, request, fromFile, fileURL, completionHandler, newCompletionHandler);
    IMHookPrepareTaskForLogging(uploadTask);
    IMHookLogRequest(@"uploadTaskWithRequest:fromFile:completionHandler:", uploadTask, request, bodyData);
    if (fileURL != nil && bodyData == nil) {
        NSLog(@"Upload Body: <file body not previewed>");
    }
    return uploadTask;
}

typedef void (^NSURLSessionStreamCompletionHandler)(NSInputStream * bodyStream);
CHOptimizedMethod3(self, void, NSURLSession,
                   URLSession, NSURLSession *, session,
                   task, NSURLSessionTask *, task,
                    needNewBodyStream, NSURLSessionStreamCompletionHandler, completionHandler) {

    NSURLRequest * request = task.currentRequest;
    IMHookLogRequest(@"URLSession:task:needNewBodyStream:", task, request, nil);
    return CHSuper3(NSURLSession, URLSession, session, task, task, needNewBodyStream, completionHandler);
}



void hookURLSession(void) {
    CHLoadLateClass(NSURLSession);
    CHLoadLateClass(NSURLSessionConfiguration);
    
    CHClassHook0(NSURLSessionConfiguration, defaultSessionConfiguration);
    CHClassHook0(NSURLSessionConfiguration, ephemeralSessionConfiguration);
    CHClassHook1(NSURLSessionConfiguration, backgroundSessionConfigurationWithIdentifier);
    CHClassHook1(NSURLSession, sessionWithConfiguration);
    CHClassHook3(NSURLSession, sessionWithConfiguration, delegate, delegateQueue);
    CHHook3(NSURLSession, initWithConfiguration, delegate, delegateQueue);
    CHHook1(NSURLSession, dataTaskWithURL);
    CHHook1(NSURLSession, dataTaskWithRequest);
    CHHook2(NSURLSession, dataTaskWithRequest, completionHandler);
    CHHook2(NSURLSession, dataTaskWithURL, completionHandler);
    
    CHHook2(NSURLSession, uploadTaskWithRequest, fromData);
    CHHook2(NSURLSession, uploadTaskWithRequest, fromFile);
    CHHook3(NSURLSession, uploadTaskWithRequest, fromData, completionHandler);
    CHHook3(NSURLSession, uploadTaskWithRequest, fromFile, completionHandler);
    CHHook3(NSURLSession, URLSession, task, needNewBodyStream);
}
