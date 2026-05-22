#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "NSData+Hex.h"

static const NSUInteger kIMHookBodyPreviewLimit = 4096;
static const NSUInteger kIMHookBinaryPreviewLimit = 1024;

static inline NSString *IMHookTruncatedString(NSString *string, NSUInteger limit) {
    if (string.length <= limit) {
        return string;
    }
    return [[string substringToIndex:limit] stringByAppendingFormat:@"\n...(truncated, total %lu chars)", (unsigned long)string.length];
}

static inline NSString *IMHookIndentedString(NSString *string) {
    if (string.length == 0) {
        return @"    <empty>";
    }
    return [@"    " stringByAppendingString:[string stringByReplacingOccurrencesOfString:@"\n" withString:@"\n    "]];
}

static inline NSString *IMHookPrettyObjectString(id object) {
    if (object == nil) {
        return @"<none>";
    }
    if ([NSJSONSerialization isValidJSONObject:object]) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (jsonString.length > 0) {
            return jsonString;
        }
    }
    return [object description];
}

static inline NSString *IMHookBodyPreview(NSData *data) {
    if (data == nil) {
        return @"<none>";
    }
    if (data.length == 0) {
        return @"<empty>";
    }
    
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    if (jsonObject != nil) {
        if ([NSJSONSerialization isValidJSONObject:jsonObject]) {
            NSData *prettyData = [NSJSONSerialization dataWithJSONObject:jsonObject options:NSJSONWritingPrettyPrinted error:nil];
            NSString *prettyString = [[NSString alloc] initWithData:prettyData encoding:NSUTF8StringEncoding];
            if (prettyString.length > 0) {
                return IMHookTruncatedString(prettyString, kIMHookBodyPreviewLimit);
            }
        } else {
            return IMHookTruncatedString([jsonObject description], kIMHookBodyPreviewLimit);
        }
    }
    
    NSString *utf8String = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (utf8String.length > 0) {
        return IMHookTruncatedString(utf8String, kIMHookBodyPreviewLimit);
    }
    
    NSUInteger binaryPreviewLength = MIN(data.length, kIMHookBinaryPreviewLimit);
    NSData *previewData = [data subdataWithRange:NSMakeRange(0, binaryPreviewLength)];
    NSString *hexPreview = dataToHexString(previewData);
    if (data.length > binaryPreviewLength) {
        return [NSString stringWithFormat:@"<binary data: %lu bytes>\n%@\n...(truncated, showing first %lu bytes as hex)", (unsigned long)data.length, hexPreview, (unsigned long)binaryPreviewLength];
    }
    return [NSString stringWithFormat:@"<binary data: %lu bytes>\n%@", (unsigned long)data.length, hexPreview];
}

static inline NSData *IMHookRequestBody(NSURLRequest *request, NSData *fallbackBody) {
    if (fallbackBody != nil) {
        return fallbackBody;
    }
    return request.HTTPBody;
}

static inline NSString *IMHookTaskIdentifierString(NSURLSessionTask *task) {
    if (task == nil) {
        return @"-";
    }
    return [NSString stringWithFormat:@"%lu", (unsigned long)task.taskIdentifier];
}

static const void *kIMHookTaskStartTimeKey = &kIMHookTaskStartTimeKey;
static const void *kIMHookTaskResponseLoggedKey = &kIMHookTaskResponseLoggedKey;

static inline void IMHookPrepareTaskForLogging(NSURLSessionTask *task) {
    if (task == nil) {
        return;
    }
    objc_setAssociatedObject(task, kIMHookTaskStartTimeKey, @(CFAbsoluteTimeGetCurrent()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(task, kIMHookTaskResponseLoggedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static inline CFAbsoluteTime IMHookTaskStartTime(NSURLSessionTask *task) {
    NSNumber *startTime = task != nil ? objc_getAssociatedObject(task, kIMHookTaskStartTimeKey) : nil;
    return startTime != nil ? startTime.doubleValue : 0;
}

static inline BOOL IMHookHasLoggedResponse(NSURLSessionTask *task) {
    NSNumber *logged = task != nil ? objc_getAssociatedObject(task, kIMHookTaskResponseLoggedKey) : nil;
    return logged.boolValue;
}

static inline void IMHookMarkResponseLogged(NSURLSessionTask *task) {
    if (task == nil) {
        return;
    }
    objc_setAssociatedObject(task, kIMHookTaskResponseLoggedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static inline void IMHookFinishTaskLogging(NSURLSessionTask *task) {
    if (task == nil) {
        return;
    }
    objc_setAssociatedObject(task, kIMHookTaskStartTimeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(task, kIMHookTaskResponseLoggedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static inline void IMHookLogRequest(NSString *source, NSURLSessionTask *task, NSURLRequest *request, NSData *bodyData) {
    if (request == nil) {
        return;
    }
    
    NSData *resolvedBody = IMHookRequestBody(request, bodyData);
    NSLog(@"================ HTTP Request ================");
    NSLog(@"Source : %@", source);
    NSLog(@"Task   : %@", IMHookTaskIdentifierString(task));
    NSLog(@"Method : %@", request.HTTPMethod ?: @"GET");
    NSLog(@"URL    : %@", request.URL.absoluteString ?: @"<nil>");
    NSLog(@"Headers:\n%@", IMHookIndentedString(IMHookPrettyObjectString(request.allHTTPHeaderFields ?: @{})));
    
    if (resolvedBody != nil) {
        NSLog(@"Body (%lu bytes):\n%@", (unsigned long)resolvedBody.length, IMHookIndentedString(IMHookBodyPreview(resolvedBody)));
    } else if (request.HTTPBodyStream != nil) {
        NSLog(@"Body   : <stream body>");
    } else {
        NSLog(@"Body   : <none>");
    }
    NSLog(@"=============================================");
}

static inline void IMHookLogResponse(NSString *source, NSURLSessionTask *task, NSURLResponse *response, NSData *data, NSError *error, CFAbsoluteTime startTime) {
    NSLog(@"================ HTTP Response ===============");
    NSLog(@"Source : %@", source);
    NSLog(@"Task   : %@", IMHookTaskIdentifierString(task));
    
    if (startTime > 0) {
        NSLog(@"Cost   : %.2f ms", (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0);
    }
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"Status : %ld", (long)httpResponse.statusCode);
        NSLog(@"URL    : %@", httpResponse.URL.absoluteString ?: @"<nil>");
        NSLog(@"Headers:\n%@", IMHookIndentedString(IMHookPrettyObjectString(httpResponse.allHeaderFields ?: @{})));
    } else if (response != nil) {
        NSLog(@"URL    : %@", response.URL.absoluteString ?: @"<nil>");
        NSLog(@"MIME   : %@", response.MIMEType ?: @"<unknown>");
        NSLog(@"Length : %lld", response.expectedContentLength);
    } else {
        NSLog(@"Response: <none>");
    }
    
    if (data != nil) {
        NSLog(@"Body (%lu bytes):\n%@", (unsigned long)data.length, IMHookIndentedString(IMHookBodyPreview(data)));
    } else {
        NSLog(@"Body   : <none>");
    }
    
    if (error != nil) {
        NSLog(@"Error  : %@", error);
    }
    NSLog(@"=============================================");
}
