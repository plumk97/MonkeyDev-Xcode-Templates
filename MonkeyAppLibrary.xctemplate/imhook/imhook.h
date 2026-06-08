//
//  imhook.h
//  imhook
//
//  Created by zhu on 2024/11/20.
//

#import <Foundation/Foundation.h>
#import "NSData+Hex.h"
#import "PassSSL.h"
// 其他 public header
#import "HookURLProtocol.h"

//! Project version number for imhook.
FOUNDATION_EXPORT double imhookVersionNumber;

//! Project version string for imhook.
FOUNDATION_EXPORT const unsigned char imhookVersionString[];

NS_ASSUME_NONNULL_BEGIN

@interface IMHookOptions : NSObject

@property (nonatomic, copy, nullable) NSString *socksHost;
@property (nonatomic, strong, nullable) NSNumber *socksPort;
@property (nonatomic, copy, nullable) NSString *teamId;

@end

void imhook(IMHookOptions * _Nullable options);
// In this header, you should import all the public headers of your framework using statements like #import <imhook/PublicHeader.h>


// 在公共头文件中定义自定义的日志宏
#ifdef DEBUG
    #define NSLog(format, ...) customNSLog((@"[imhook] " format), ##__VA_ARGS__)
#else
    #define NSLog(format, ...)
#endif

// 自定义日志函数
static inline void customNSLog(NSString * _Nonnull format, ...) {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    fprintf(stderr, "%s\n", [formattedString UTF8String]);
}


NS_ASSUME_NONNULL_END
