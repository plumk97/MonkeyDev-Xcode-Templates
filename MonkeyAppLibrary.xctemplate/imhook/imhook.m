//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  imhook.m
//  imhook
//
//  Created by zhu on 2024/11/20.
//  Copyright (c) 2024 ___ORGANIZATIONNAME___. All rights reserved.
//

#import "imhook.h"
#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import "URLSessionHook.h"
#import "URLConnection.h"

@implementation IMHookOptions
@end

void imhook(IMHookOptions * _Nullable options) {
    IMHookConfigureSOCKSProxy(options.socksHost, options.socksPort);
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstrict-prototypes"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// MARK: - 腾讯云IM
CHDeclareClass(V2TIMManager)
CHOptimizedMethod2(self, bool, V2TIMManager, initSDK, int, sdkAppID, config, id, config) {
    NSLog(@"腾讯云IM appId: %d", sdkAppID);
    return CHSuper2(V2TIMManager, initSDK, sdkAppID, config, config);
}

CHOptimizedMethod4(self, bool, V2TIMManager,
                   login, NSString *, userID,
                   userSig, NSString *, userSig,
                   succ, id, succ,
                   fail, id, fail) {
    NSLog(@"腾讯云IM UserId: %@, userSig: %@", userID, userSig);
    return CHSuper4(V2TIMManager,
                    login, userID,
                    userSig, userSig,
                    succ, succ,
                    fail, fail
                    );
}

// MARK: - 网易云IM
CHDeclareClass(NIMSDKOption)
CHOptimizedClassMethod1(self, id, NIMSDKOption, optionWithAppKey, NSString *, key) {
    NSLog(@"网易云信 appKey: %@", key);
    return CHSuper1(NIMSDKOption, optionWithAppKey, key);
}

CHDeclareClass(NIMSDK)
CHOptimizedMethod2(self, void, NIMSDK,
                        registerWithAppID, NSString *, key,
                        cerName, NSString *, cerName
                        ) {
    NSLog(@"网易云信 appKey: %@", key);
    return CHSuper2(NIMSDK, registerWithAppID, key, cerName, cerName);
}

CHDeclareClass(NIMLoginManager)
CHOptimizedMethod5(self, void, NIMLoginManager,
                   login, NSString *, account,
                   token, NSString *, token,
                   authType, int, authType,
                   loginExt, NSString *, loginExt,
                   completion, id, completion) {
    NSLog(@"网易云信 account: %@, token: %@, authType: %d, loginExt: %@", account, token, authType, loginExt);
    return CHSuper5(NIMLoginManager,
                    login, account,
                    token, token,
                    authType, authType,
                    loginExt, loginExt,
                    completion, completion);
}


// MARK: - 融云IM
CHDeclareClass(RCCoreClient)
CHOptimizedMethod1(self, void, RCCoreClient, initWithAppKey, NSString *, appKey) {
    NSLog(@"融云 appKey: %@", appKey);
    return CHSuper1(RCCoreClient, initWithAppKey, appKey);
}

CHOptimizedMethod2(self, void, RCCoreClient, initWithAppKey, NSString *, appKey, option, id, option) {
    NSLog(@"融云 appKey: %@", appKey);
    return CHSuper2(RCCoreClient, initWithAppKey, appKey, option, option);
}

CHOptimizedMethod4(self, void, RCCoreClient,
                   connectWithToken, NSString *, token,
                   dbOpened, id, dbOpenedBlock,
                   success, id, successBlock,
                   error, id, errorBlock) {
    NSLog(@"融云 token: %@", token);
    return CHSuper4(RCCoreClient, connectWithToken, token, dbOpened, dbOpenedBlock, success, successBlock, error, errorBlock);
}

CHOptimizedMethod5(self, void, RCCoreClient,
                   connectWithToken, NSString *,token,
                   timeLimit, int, timeLimit,
                   dbOpened, id, dbOpened,
                   success, id, success,
                   error, id, error) {
    
    NSLog(@"融云 token: %@", token);
    return CHSuper5(RCCoreClient, connectWithToken, token, timeLimit, timeLimit, dbOpened, dbOpened, success, success, error, error);
}


// MARK: - AFHTTPSessionManager

CHConstructor{
    NSLog(@"imhook 注入");
    NSLog(@"home %@", NSHomeDirectory());
    
    // MARK: - 腾讯云IM注册
    CHLoadLateClass(V2TIMManager);
    CHHook2(V2TIMManager, initSDK, config);
    CHHook4(V2TIMManager, login, userSig, succ, fail);
    
    // MARK: - 网易云IM注册
    CHLoadLateClass(NIMSDK);
    CHClassHook2(NIMSDK, registerWithAppID, cerName);
    
    CHLoadLateClass(NIMSDKOption);
    CHClassHook1(NIMSDKOption, optionWithAppKey);
    
    CHLoadLateClass(NIMLoginManager);
    CHHook5(NIMLoginManager, login, token, authType, loginExt, completion);
    
    
    // MARK: - 融云
    CHLoadLateClass(RCCoreClient);
    CHHook1(RCCoreClient, initWithAppKey);
    CHHook2(RCCoreClient, initWithAppKey, option);
    CHHook4(RCCoreClient, connectWithToken, dbOpened, success, error);
    CHHook5(RCCoreClient, connectWithToken, timeLimit, dbOpened, success, error);
    

    hookURLSession();
    hookURLConnection();
}

#pragma clang diagnostic pop
