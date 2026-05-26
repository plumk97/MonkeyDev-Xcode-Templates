#import "PassSSL.h"

#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>

#include "../fishhook/fishhook.h"

typedef int (*IMSSLCustomVerifyCallback)(void *ssl, uint8_t *out_alert);
typedef void(^IMURLSessionChallengeCompletionHandler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential);

static OSStatus (*orig_SecTrustEvaluate)(SecTrustRef trust, SecTrustResultType *result);
static Boolean (*orig_SecTrustEvaluateWithError)(SecTrustRef trust, CFErrorRef *error);
static OSStatus (*orig_SecTrustEvaluateAsyncWithError)(SecTrustRef trust, dispatch_queue_t queue, SecTrustWithErrorCallback result);
static void (*orig_SSL_set_custom_verify)(void *ssl, int mode, IMSSLCustomVerifyCallback callback);
static const char *(*orig_SSL_get_psk_identity)(const void *ssl);
static void (*orig_SSL_CTX_set_custom_verify)(void *ctx, int mode, IMSSLCustomVerifyCallback callback);
static void (*orig_sec_protocol_options_set_verify_block)(sec_protocol_options_t options, sec_protocol_verify_t verify_block, dispatch_queue_t verify_block_queue);
static SEL kIMOriginalTaskChallengeSelector = NULL;

typedef void (*IMAlamofireTaskChallengeIMP)(id, SEL, NSURLSession *, NSURLSessionTask *, NSURLAuthenticationChallenge *, IMURLSessionChallengeCompletionHandler);

static int im_ssl_custom_verify_always_ok(void *ssl, uint8_t *out_alert) {
    if (out_alert != NULL) {
        *out_alert = 0;
    }
    return 0;
}

static OSStatus hook_SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
    NSLog(@"[PassSSL] SecTrustEvaluate");

    OSStatus status = orig_SecTrustEvaluate(trust, result);

    NSLog(@"status = %d", (int)status);
    if (result != NULL) {
        NSLog(@"result = %d", (int)*result);
        *result = kSecTrustResultProceed;
    }

    return errSecSuccess;
}

static Boolean hook_SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error) {
    NSLog(@"[PassSSL] SecTrustEvaluateWithError");

    Boolean success = orig_SecTrustEvaluateWithError(trust, error);

    NSLog(@"success = %d", success);
    if (error != NULL) {
        *error = nil;
    }

    return true;
}

static OSStatus hook_SecTrustEvaluateAsyncWithError(SecTrustRef trust, dispatch_queue_t queue, SecTrustWithErrorCallback result) {
    NSLog(@"[PassSSL] SecTrustEvaluateAsyncWithError");

    if (result != nil) {
        if (queue != nil) {
            dispatch_async(queue, ^{
                result(trust, true, nil);
            });
        } else {
            result(trust, true, nil);
        }
    }

    return errSecSuccess;
}

static void hook_SSL_set_custom_verify(void *ssl, int mode, IMSSLCustomVerifyCallback callback) {
    NSLog(@"[PassSSL] SSL_set_custom_verify mode=%d callback=%p", mode, callback);

    if (orig_SSL_set_custom_verify != NULL) {
        orig_SSL_set_custom_verify(ssl, 0, im_ssl_custom_verify_always_ok);
    }
}

static const char *hook_SSL_get_psk_identity(const void *ssl) {
    NSLog(@"[PassSSL] SSL_get_psk_identity");

    if (orig_SSL_get_psk_identity != NULL) {
        const char *identity = orig_SSL_get_psk_identity(ssl);
        if (identity != NULL && identity[0] != '\0') {
            return identity;
        }
    }

    return "notarealPSKidentity";
}

static void hook_SSL_CTX_set_custom_verify(void *ctx, int mode, IMSSLCustomVerifyCallback callback) {
    NSLog(@"[PassSSL] SSL_CTX_set_custom_verify mode=%d callback=%p", mode, callback);

    if (orig_SSL_CTX_set_custom_verify != NULL) {
        orig_SSL_CTX_set_custom_verify(ctx, 0, im_ssl_custom_verify_always_ok);
    }
}

static void hook_sec_protocol_options_set_verify_block(sec_protocol_options_t options, sec_protocol_verify_t verify_block, dispatch_queue_t verify_block_queue) {
    NSLog(@"[PassSSL] sec_protocol_options_set_verify_block verify_block=%p", verify_block);

    if (orig_sec_protocol_options_set_verify_block == NULL) {
        return;
    }

    dispatch_queue_t callbackQueue = verify_block_queue ?: dispatch_get_main_queue();
    orig_sec_protocol_options_set_verify_block(options, ^(sec_protocol_metadata_t metadata, sec_trust_t trust_ref, sec_protocol_verify_complete_t complete) {
        if (complete != nil) {
            complete(true);
        }
    }, callbackQueue);
}

static BOOL IMMTGAFEvaluateServerTrust(id self, SEL _cmd, SecTrustRef trust) {
    NSLog(@"[PassSSL] MTGAFSecurityPolicy evaluateServerTrust");
    return YES;
}

static BOOL IMMTGAFEvaluateServerTrustForDomain(id self, SEL _cmd, SecTrustRef trust, NSString *domain) {
    NSLog(@"[PassSSL] MTGAFSecurityPolicy evaluateServerTrust:forDomain: %@", domain);
    return YES;
}

static NSURLCredential *IMCreateServerTrustCredential(NSURLAuthenticationChallenge *challenge) {
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    if (serverTrust == NULL) {
        return nil;
    }

    return [NSURLCredential credentialForTrust:serverTrust];
}

static void IMAlamofireTaskDidReceiveChallenge(id self, SEL _cmd, NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, IMURLSessionChallengeCompletionHandler completionHandler) {
    NSURLCredential *serverTrustCredential = IMCreateServerTrustCredential(challenge);
    if (serverTrustCredential != nil) {
        NSLog(@"[PassSSL] Alamofire task challenge bypass %@", challenge.protectionSpace.host);
        if (completionHandler != nil) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, serverTrustCredential);
        }
        return;
    }

    ((IMAlamofireTaskChallengeIMP)objc_msgSend)(self, kIMOriginalTaskChallengeSelector, session, task, challenge, completionHandler);
}

static void IMEnsureTaskChallengeSelectorInitialized(void) {
    static dispatch_once_t selectorOnceToken;
    dispatch_once(&selectorOnceToken, ^{
        kIMOriginalTaskChallengeSelector = NSSelectorFromString(@"imhook_original_URLSession_task_didReceiveChallenge_completionHandler:");
    });
}

static BOOL IMClassImplementsSelectorDirectly(Class cls, SEL selector) {
    if (cls == Nil || selector == NULL) {
        return NO;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    BOOL found = NO;

    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }

    free(methods);
    return found;
}

static BOOL IMClassIsSubclassOfClass(Class cls, Class parentClass) {
    if (cls == Nil || parentClass == Nil) {
        return NO;
    }

    for (Class currentClass = cls; currentClass != Nil; currentClass = class_getSuperclass(currentClass)) {
        if (currentClass == parentClass) {
            return YES;
        }
    }

    return NO;
}

static void IMInstallTaskChallengeHookForClass(Class targetClass) {
    IMEnsureTaskChallengeSelectorInitialized();

    if (targetClass == Nil) {
        return;
    }

    SEL selector = @selector(URLSession:task:didReceiveChallenge:completionHandler:);
    Method method = class_getInstanceMethod(targetClass, selector);
    if (method == NULL || IMClassImplementsSelectorDirectly(targetClass, kIMOriginalTaskChallengeSelector)) {
        return;
    }

    const char *typeEncoding = method_getTypeEncoding(method);
    class_addMethod(targetClass, kIMOriginalTaskChallengeSelector, method_getImplementation(method), typeEncoding);
    class_replaceMethod(targetClass, selector, (IMP)IMAlamofireTaskDidReceiveChallenge, typeEncoding);
    NSLog(@"[PassSSL] Installed challenge hook for %@", NSStringFromClass(targetClass));
}

static void IMInstallAlamofireDelegateHooks(void) {
    Class alamofireSessionDelegateClass = NSClassFromString(@"Alamofire.SessionDelegate");
    if (alamofireSessionDelegateClass == Nil) {
        alamofireSessionDelegateClass = objc_getClass("_TtC9Alamofire15SessionDelegate");
    }
    if (alamofireSessionDelegateClass == Nil) {
        return;
    }

    SEL selector = @selector(URLSession:task:didReceiveChallenge:completionHandler:);
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        return;
    }

    Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * classCount);
    classCount = objc_getClassList(classes, classCount);

    for (int index = 0; index < classCount; index++) {
        Class targetClass = classes[index];
        if (!IMClassIsSubclassOfClass(targetClass, alamofireSessionDelegateClass)) {
            continue;
        }
        if (!IMClassImplementsSelectorDirectly(targetClass, selector)) {
            continue;
        }

        IMInstallTaskChallengeHookForClass(targetClass);
    }

    free(classes);
}

static void IMInstallMTGAFSecurityPolicyHook(void) {
    Class policyClass = NSClassFromString(@"MTGAFSecurityPolicy");
    if (policyClass == Nil) {
        return;
    }

    SEL trustSelector = NSSelectorFromString(@"evaluateServerTrust:");
    Method trustMethod = class_getInstanceMethod(policyClass, trustSelector);
    if (trustMethod != NULL) {
        class_replaceMethod(policyClass, trustSelector, (IMP)IMMTGAFEvaluateServerTrust, method_getTypeEncoding(trustMethod));
    }

    SEL domainSelector = NSSelectorFromString(@"evaluateServerTrust:forDomain:");
    Method domainMethod = class_getInstanceMethod(policyClass, domainSelector);
    if (domainMethod != NULL) {
        class_replaceMethod(policyClass, domainSelector, (IMP)IMMTGAFEvaluateServerTrustForDomain, method_getTypeEncoding(domainMethod));
    }

    NSLog(@"[PassSSL] Installed MTGAFSecurityPolicy hook");
}

void hookPassSSL(void) {
    static dispatch_once_t fishhookOnceToken;

    dispatch_once(&fishhookOnceToken, ^{
        rebind_symbols((struct rebinding[7]){
            { "SecTrustEvaluate", (void *)hook_SecTrustEvaluate, (void **)&orig_SecTrustEvaluate },
            { "SecTrustEvaluateWithError", (void *)hook_SecTrustEvaluateWithError, (void **)&orig_SecTrustEvaluateWithError },
            { "SecTrustEvaluateAsyncWithError", (void *)hook_SecTrustEvaluateAsyncWithError, (void **)&orig_SecTrustEvaluateAsyncWithError },
            { "SSL_set_custom_verify", (void *)hook_SSL_set_custom_verify, (void **)&orig_SSL_set_custom_verify },
            { "SSL_get_psk_identity", (void *)hook_SSL_get_psk_identity, (void **)&orig_SSL_get_psk_identity },
            { "SSL_CTX_set_custom_verify", (void *)hook_SSL_CTX_set_custom_verify, (void **)&orig_SSL_CTX_set_custom_verify },
            { "sec_protocol_options_set_verify_block", (void *)hook_sec_protocol_options_set_verify_block, (void **)&orig_sec_protocol_options_set_verify_block },
        }, 7);
    });

    IMInstallAlamofireDelegateHooks();
    IMInstallMTGAFSecurityPolicyHook();
}
