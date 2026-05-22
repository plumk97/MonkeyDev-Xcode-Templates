//
//  URLSessionHook.h
//  imhook
//
//  Created by zhu on 2025/1/16.
//

#import <Foundation/Foundation.h>


void IMHookConfigureSOCKSProxy(NSString * _Nullable host, NSNumber * _Nullable port);
void hookURLSession(void);
