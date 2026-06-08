//
//  AppClean.m
//  BluedInternationalDylib
//
//  Created by ayo on 2025/11/11.
//

#import "AppClean.h"
#include <dlfcn.h>
#include "fishhook.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h> // 需要引入 WebKit

// MARK: - 1. 拦截风控队列
static void (*orig_dispatch_async)(dispatch_queue_t queue, dispatch_block_t block);

static void my_dispatch_async(dispatch_queue_t queue, dispatch_block_t block) {
    const char *label = dispatch_queue_get_label(queue);
    // 拦截字节系的风控队列，非常关键
    if (label && strcmp(label, "ies.safe.guard.queue") == 0) {
        return;
    }
    orig_dispatch_async(queue, block);
}


__attribute__((constructor))
static void init(void) {
    rebind_symbols((struct rebinding[1]) {
            {"dispatch_async", my_dispatch_async, (void *)&orig_dispatch_async},
        }, 1);
}


// MARK: - 2. 增强版清理工具

// 清理 HTTP Cookies
static void clearCookies(void) {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// 清理 URL 缓存
static void clearURLCache(void) {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

// 清理 WebKit 数据 (iOS 9+)
// 注意：这个操作是异步的，但在杀进程前调用尽量触发清理
static void clearWebData(void) {
    if (@available(iOS 9.0, *)) {
        NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{
            // NSLog(@"WebKit Data Cleared");
        }];
    }
}

static void clearUserDefaults(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // 获取所有的键
    NSDictionary *dict = [defaults dictionaryRepresentation];

    // 删除所有键
    for (NSString *key in dict) {
        [defaults removeObjectForKey:key];
    }

    // 立即同步
    [defaults synchronize];
}

static void clearAppData(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 1. 清除 Cookies 和 Web 缓存 (程序层面)
    clearCookies();
    clearURLCache();
    clearWebData();

    // 2. Documents
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (docs) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:docs error:nil];
        for (NSString *file in contents) {
            [fm removeItemAtPath:[docs stringByAppendingPathComponent:file] error:nil];
        }
    }

    // 3. Library (暴力清理：Caches, Preferences, Application Support, Cookies, WebKit)
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    if (lib) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:lib error:nil];
        for (NSString *file in contents) {
            [fm removeItemAtPath:[lib stringByAppendingPathComponent:file] error:nil];
        }
    }

    // 4. tmp
    NSString *tmp = NSTemporaryDirectory();
    if (tmp) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:tmp error:nil];
        for (NSString *file in contents) {
            [fm removeItemAtPath:[tmp stringByAppendingPathComponent:file] error:nil];
        }
    }
    
    // 5. 
    clearUserDefaults();
    
    // 6. 剪切板
    [UIPasteboard generalPasteboard].items = @[];
}




static void clearKeychain(void) {
    // 这种通用删除通常够用，但如果 App 用了特定 Access Group，可能删不掉。
    // 如果发现删不干净，需要 Hook SecItemAdd 抓取它用的 Access Group 是什么。
    
    NSArray *secItemClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    for (id secItemClass in secItemClasses) {
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        query[(__bridge id)kSecClass] = secItemClass;
        // 尝试匹配所有项目
        // query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll; // Delete 不需要 Limit，加上反而可能报错
        
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
         NSLog(@"Delete Class: %@ Status: %d", secItemClass, (int)status);
    }
}

static void killAppForce(void) {
    pid_t pid = getpid();
    kill(pid, SIGKILL);
}

// 对外暴露的清理函数
void appClean(void) {
    NSLog(@"[AppClean] Start Cleaning...");
    clearKeychain();
    clearAppData();
    NSLog(@"[AppClean] Cleaning Finished. Killing App...");
    killAppForce();
}
