#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <sys/syscall.h>
#include <dlfcn.h>
#include "../fishhook/fishhook.h"
#include <string.h>
#import "MockDevice.h"
#import <UIKit/UIKit.h>
#import <CaptainHook/CaptainHook.h>
#import <sys/stat.h>
#include <sys/mount.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <sys/utsname.h>
#include <unistd.h>
#import <fcntl.h>

static BOOL MDIsEmbeddedProvisionFilename(NSString *filename) {
    if (filename.length == 0) {
        return NO;
    }
    return [[filename lowercaseString] isEqualToString:@"embedded.mobileprovision"];
}

static BOOL MDIsEmbeddedProvisionPath(NSString *path) {
    if (path.length == 0) {
        return NO;
    }
    return MDIsEmbeddedProvisionFilename(path.lastPathComponent);
}

static BOOL MDIsEmbeddedProvisionURL(NSURL *url) {
    if (url == nil) {
        return NO;
    }
    NSString *path = url.isFileURL ? url.path : url.absoluteString;
    return MDIsEmbeddedProvisionPath(path);
}

static bool MDIsEmbeddedProvisionCString(const char *path) {
    if (path == NULL) {
        return false;
    }
    return MDIsEmbeddedProvisionPath([NSString stringWithUTF8String:path]);
}

static int MDProvisionNotFound(NSError **error) {
    if (error != NULL) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFileReadNoSuchFileError
                                 userInfo:nil];
    }
    errno = ENOENT;
    return -1;
}

static NSData *MDProvisionDataNotFound(NSError **error) {
    MDProvisionNotFound(error);
    return nil;
}

static NSString *MDMockLanguageCode(void) {
    NSString *languageCode = [MockDevice shared].system.languageCode;
    return languageCode.length > 0 ? languageCode : @"en";
}

static NSString *MDMockLocaleIdentifier(void) {
    return @"en_US";
}

static NSString *MDMockTimeZoneIdentifier(void) {
    NSString *timeZone = [MockDevice shared].system.timeZone;
    return timeZone.length > 0 ? timeZone : @"America/New_York";
}

static NSLocale *MDMockLocale(void) {
    return [NSLocale localeWithLocaleIdentifier:MDMockLocaleIdentifier()];
}

static NSTimeZone *MDMockTimeZone(void) {
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:MDMockTimeZoneIdentifier()];
    return timeZone ?: [NSTimeZone timeZoneWithName:@"America/New_York"];
}


// MARK: - Anti Anti DEBUG
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif

#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif

#ifndef CS_GET_TASK_ALLOW
#define CS_GET_TASK_ALLOW 0x00000004
#endif

#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000
#endif

static int (*orig_ptrace)(int request, pid_t pid, caddr_t addr, int data);
static void* (*orig_dlsym)(void* handle, const char* symbol);
static int (*orig_sysctl)(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static pid_t (*orig_getppid)(void);
static int (*orig_csops)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
static int (*orig_csops_audittoken)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, void *token);
static kern_return_t (*orig_task_get_exception_ports)(task_t task, exception_mask_t exception_mask, exception_mask_array_t masks, mach_msg_type_number_t *masksCnt, exception_handler_array_t old_handlers, exception_behavior_array_t old_behaviors, exception_flavor_array_t old_flavors);
static int (*orig_access)(const char *path, int amode);
static FILE *(*orig_fopen)(const char *restrict filename, const char *restrict mode);
static int (*orig_open)(const char *path, int oflag, ...);
static int (*orig_openat)(int fd, const char *path, int oflag, ...);
static int (*orig_lstat)(const char *path, struct stat *buf);
static int (*orig_uname)(struct utsname *value);
static const char *(*orig_dyld_get_image_name)(uint32_t index);
static uint32_t (*orig_dyld_image_count)(void);

static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static pid_t my_getppid(void);
static int my_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
static int my_csops_audittoken(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, void *token);
static kern_return_t my_task_get_exception_ports(task_t task, exception_mask_t exception_mask, exception_mask_array_t masks, mach_msg_type_number_t *masksCnt, exception_handler_array_t old_handlers, exception_behavior_array_t old_behaviors, exception_flavor_array_t old_flavors);

static void MDSanitizeKinfoProc(struct kinfo_proc *kp) {
    if (kp == NULL) {
        return;
    }
    kp->kp_proc.p_flag &= ~P_TRACED;
    kp->kp_proc.p_oppid = 0;
    kp->kp_eproc.e_ppid = 0;
}

static void MDSanitizeCodeSignFlags(void *useraddr, size_t usersize) {
    if (useraddr == NULL || usersize < sizeof(uint32_t)) {
        return;
    }
    uint32_t *flags = (uint32_t *)useraddr;
    *flags &= ~(CS_DEBUGGED | CS_GET_TASK_ALLOW);
}

static void MDSanitizeExceptionPorts(exception_mask_array_t masks,
                                     mach_msg_type_number_t *masksCnt,
                                     exception_handler_array_t old_handlers,
                                     exception_behavior_array_t old_behaviors,
                                     exception_flavor_array_t old_flavors) {
    if (masks == NULL || masksCnt == NULL) {
        return;
    }

    mach_msg_type_number_t inputCount = *masksCnt;
    mach_msg_type_number_t outputCount = 0;

    for (mach_msg_type_number_t index = 0; index < inputCount; index++) {
        exception_mask_t sanitizedMask = masks[index] & ~(EXC_MASK_BREAKPOINT | EXC_MASK_SOFTWARE);
        mach_port_t handler = old_handlers != NULL ? old_handlers[index] : MACH_PORT_NULL;

        if (sanitizedMask == 0 || handler == MACH_PORT_NULL) {
            continue;
        }

        masks[outputCount] = sanitizedMask;
        if (old_handlers != NULL) {
            old_handlers[outputCount] = handler;
        }
        if (old_behaviors != NULL) {
            old_behaviors[outputCount] = old_behaviors[index];
        }
        if (old_flavors != NULL) {
            old_flavors[outputCount] = old_flavors[index];
        }
        outputCount++;
    }

    *masksCnt = outputCount;
}

static int my_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == PT_DENY_ATTACH) {
        NSLog(@"[AntiAntiDebug] ptrace(PT_DENY_ATTACH) blocked");
        errno = EPERM;      // 必须设置
        return -1;          // 必须返回 -1
    }
    return orig_ptrace(request, pid, addr, data);
}

static void* my_dlsym(void* handle, const char* symbol) {
    if (symbol == NULL) {
        return orig_dlsym(handle, symbol);
    }

    if (strcmp(symbol, "ptrace") == 0 || strcmp(symbol, "_ptrace") == 0) {
        return my_ptrace;
    }
    if (strcmp(symbol, "sysctl") == 0 || strcmp(symbol, "_sysctl") == 0) {
        return my_sysctl;
    }
    if (strcmp(symbol, "getppid") == 0 || strcmp(symbol, "_getppid") == 0) {
        return my_getppid;
    }
    if (strcmp(symbol, "csops") == 0 || strcmp(symbol, "_csops") == 0) {
        return my_csops;
    }
    if (strcmp(symbol, "csops_audittoken") == 0 || strcmp(symbol, "_csops_audittoken") == 0) {
        return my_csops_audittoken;
    }
    if (strcmp(symbol, "task_get_exception_ports") == 0 || strcmp(symbol, "_task_get_exception_ports") == 0) {
        return my_task_get_exception_ports;
    }

    return orig_dlsym(handle, symbol);
}

static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    
    // MARK: - 启动时间
    // ---------- 1. BootTime (KERN_BOOTTIME) Hook ----------
    if (namelen == 2 &&
        name[0] == CTL_KERN &&
        name[1] == KERN_BOOTTIME)
    {
        if (oldp && oldlenp && *oldlenp >= sizeof(struct timeval))
        {
            time_t now = time(NULL);

            // 伪造：设备启动于 N 小时前（随机 6~40 小时）
            int hours = arc4random_uniform(35) + 6;
            time_t fakeBoot = now - hours * 3600;

            struct timeval tv;
            tv.tv_sec = fakeBoot;
            tv.tv_usec = 0;

            memcpy(oldp, &tv, sizeof(tv));
            *oldlenp = sizeof(tv);
            return 0;
        }
    }

    
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    
    // 过调试
    if (ret == 0 &&
        namelen == 4 &&
        name[0] == CTL_KERN &&
        name[1] == KERN_PROC &&
        name[2] == KERN_PROC_PID &&
        oldp && oldlenp &&
        *oldlenp >= sizeof(struct kinfo_proc))
    {
        MDSanitizeKinfoProc((struct kinfo_proc *)oldp);
    }

    return ret;
}

static pid_t my_getppid(void) {
    return 1;
}

static int my_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int result = orig_csops(pid, ops, useraddr, usersize);
    if (result == 0 && pid == getpid() && ops == CS_OPS_STATUS) {
        MDSanitizeCodeSignFlags(useraddr, usersize);
    }
    return result;
}

static int my_csops_audittoken(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, void *token) {
    int result = orig_csops_audittoken(pid, ops, useraddr, usersize, token);
    if (result == 0 && pid == getpid() && ops == CS_OPS_STATUS) {
        MDSanitizeCodeSignFlags(useraddr, usersize);
    }
    return result;
}

static kern_return_t my_task_get_exception_ports(task_t task,
                                                 exception_mask_t exception_mask,
                                                 exception_mask_array_t masks,
                                                 mach_msg_type_number_t *masksCnt,
                                                 exception_handler_array_t old_handlers,
                                                 exception_behavior_array_t old_behaviors,
                                                 exception_flavor_array_t old_flavors) {
    kern_return_t result = orig_task_get_exception_ports(task, exception_mask, masks, masksCnt, old_handlers, old_behaviors, old_flavors);
    if (result == KERN_SUCCESS && task == mach_task_self()) {
        MDSanitizeExceptionPorts(masks, masksCnt, old_handlers, old_behaviors, old_flavors);
    }
    return result;
}

static int my_access(const char *path, int amode) {
    if (MDIsEmbeddedProvisionCString(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_access(path, amode);
}

static FILE *my_fopen(const char *filename, const char *mode) {
    if (MDIsEmbeddedProvisionCString(filename)) {
        errno = ENOENT;
        return NULL;
    }
    return orig_fopen(filename, mode);
}

static int my_open(const char *path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list args;
        va_start(args, oflag);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    
    if (MDIsEmbeddedProvisionCString(path)) {
        errno = ENOENT;
        return -1;
    }
    
    if (oflag & O_CREAT) {
        return orig_open(path, oflag, mode);
    }
    return orig_open(path, oflag);
}

static int my_openat(int fd, const char *path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list args;
        va_start(args, oflag);
        mode = (mode_t)va_arg(args, int);
        va_end(args);
    }
    
    if (MDIsEmbeddedProvisionCString(path)) {
        errno = ENOENT;
        return -1;
    }
    
    if (oflag & O_CREAT) {
        return orig_openat(fd, path, oflag, mode);
    }
    return orig_openat(fd, path, oflag);
}


// MARK: - 设备code
// 原始 sysctlbyname 函数指针
static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
static int my_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL &&
        (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0)) {
        const char *spoofCStr = [MockDevice shared].machineCode.UTF8String;
        size_t spoofLen = strlen(spoofCStr) + 1;
        
        if (oldlenp != NULL) {
            if (oldp == NULL) {
                *oldlenp = spoofLen;
                return 0;
            }
            
            if (*oldlenp < spoofLen) {
                *oldlenp = spoofLen;
                errno = ENOMEM;
                return -1;
            }
            
            memcpy(oldp, spoofCStr, spoofLen);
            *oldlenp = spoofLen;
            return 0;
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int my_uname(struct utsname *value) {
    int result = orig_uname(value);
    if (result == 0 && value != NULL) {
        strlcpy(value->machine, [MockDevice shared].machineCode.UTF8String, sizeof(value->machine));
    }
    return result;
}



// MARK: - 库检测
static const char *hidden_libs[] = {
    "___FILEBASENAME___",
    "libsubstrate",
    "libcycript",
    "RevealServer",
    NULL
};

// 是否属于隐藏库
static bool isHiddenImage(const char *path) {
    if (!path) return false;
    NSString *imagePath = [[NSString stringWithUTF8String:path] lowercaseString];
    if (imagePath.length == 0) {
        return false;
    }
    for (int i = 0; hidden_libs[i] != NULL; i++) {
        NSString *needle = [[NSString stringWithUTF8String:hidden_libs[i]] lowercaseString];
        if ([imagePath containsString:needle]) {
            return true;
        }
    }
    return false;
}

static uint32_t MDVisibleImageIndexToRealIndex(uint32_t visibleIndex) {
    uint32_t realCount = orig_dyld_image_count();
    uint32_t visibleCount = 0;
    
    for (uint32_t i = 0; i < realCount; i++) {
        const char *name = orig_dyld_get_image_name(i);
        if (isHiddenImage(name)) {
            continue;
        }
        if (visibleCount == visibleIndex) {
            return i;
        }
        visibleCount++;
    }
    
    return UINT32_MAX;
}

static const char * my_dyld_get_image_name(uint32_t index) {
    uint32_t realIndex = MDVisibleImageIndexToRealIndex(index);
    if (realIndex == UINT32_MAX) {
        return NULL;
    }
    return orig_dyld_get_image_name(realIndex);
}

static uint32_t my_dyld_image_count(void) {
    uint32_t real = orig_dyld_image_count();
    uint32_t hide = 0;

    for (uint32_t i = 0; i < real; i++) {
        const char *name = orig_dyld_get_image_name(i);
        if (name && isHiddenImage(name)) {
            hide++;
        }
    }

    return real - hide;
}

// MARK: - 屏幕相关
CHDeclareClass(UIScreen)
CHOptimizedMethod0(self, CGFloat, UIScreen, brightness) {
    return [MockDevice shared].display.screenBrightness;
}
//CHOptimizedMethod0(self, CGFloat, UIScreen, scale) {
//    return [MockDevice shared].display.screenDensity;
//}
//CHOptimizedMethod0(self, CGRect, UIScreen, bounds) {
//    CGFloat w = [MockDevice shared].display.screenWidth;
//    CGFloat h = [MockDevice shared].display.screenHeight;
//    return CGRectMake(0, 0, w, h);
//}


// MARK: - UIDevice
CHDeclareClass(UIDevice);

// 1. Hook identifierForVendor (IDFV)
CHMethod0(NSUUID *, UIDevice, identifierForVendor) {
    return MockDevice.shared.idfv;
}

CHMethod0(NSString *, UIDevice, name) {
    return [MockDevice shared].hardware.deviceSettingName;
}

CHMethod0(NSString *, UIDevice, model) {
    return [MockDevice shared].hardware.deviceModel;
}

CHMethod0(NSString *, UIDevice, localizedModel) {
    return [MockDevice shared].hardware.deviceLocalizedModel;
}

CHMethod0(NSString *, UIDevice, systemName) {
    return [MockDevice shared].system.systemName;
}

CHMethod0(NSString *, UIDevice, systemVersion) {
    return [MockDevice shared].system.systemVersion;
}

// MARK: - 电量
CHOptimizedMethod0(self, CGFloat, UIDevice, batteryLevel) {
    return [MockDevice shared].battery.batteryQuantity;
}

CHOptimizedMethod0(self, UIDeviceBatteryState, UIDevice, batteryState) {
    NSString *state = [MockDevice shared].battery.batteryState;
    if ([state isEqualToString:@"Charging"]) {
        return UIDeviceBatteryStateCharging;
    }
    if ([state isEqualToString:@"Full"]) {
        return UIDeviceBatteryStateFull;
    }
    return UIDeviceBatteryStateUnplugged;
}

// MARK: - Language / Locale
CHDeclareClass(NSLocale);

CHOptimizedClassMethod0(self, NSArray<NSString *> *, NSLocale, preferredLanguages) {
    return @[MDMockLanguageCode()];
}

CHOptimizedClassMethod0(self, NSLocale *, NSLocale, currentLocale) {
    return MDMockLocale();
}

CHOptimizedClassMethod0(self, NSLocale *, NSLocale, autoupdatingCurrentLocale) {
    return MDMockLocale();
}

// MARK: - TimeZone
CHDeclareClass(NSTimeZone);

CHOptimizedClassMethod0(self, NSTimeZone *, NSTimeZone, localTimeZone) {
    return MDMockTimeZone();
}

CHOptimizedClassMethod0(self, NSTimeZone *, NSTimeZone, systemTimeZone) {
    return MDMockTimeZone();
}

CHOptimizedClassMethod0(self, NSTimeZone *, NSTimeZone, defaultTimeZone) {
    return MDMockTimeZone();
}

// MARK: - UserDefaults locale values
CHDeclareClass(NSUserDefaults);

CHOptimizedMethod1(self, id, NSUserDefaults, objectForKey, NSString *, defaultName) {
    if ([defaultName isEqualToString:@"AppleLanguages"]) {
        return @[MDMockLanguageCode()];
    }
    if ([defaultName isEqualToString:@"AppleLocale"]) {
        return MDMockLocaleIdentifier();
    }
    return CHSuper1(NSUserDefaults, objectForKey, defaultName);
}

CHOptimizedMethod1(self, NSArray<NSString *> *, NSUserDefaults, stringArrayForKey, NSString *, defaultName) {
    if ([defaultName isEqualToString:@"AppleLanguages"]) {
        return @[MDMockLanguageCode()];
    }
    return CHSuper1(NSUserDefaults, stringArrayForKey, defaultName);
}

CHOptimizedMethod1(self, NSString *, NSUserDefaults, stringForKey, NSString *, defaultName) {
    if ([defaultName isEqualToString:@"AppleLocale"]) {
        return MDMockLocaleIdentifier();
    }
    return CHSuper1(NSUserDefaults, stringForKey, defaultName);
}

// MARK: - IDFV
//CHDeclareClass(ASIdentifierManager);
//
//CHMethod0(NSUUID *, ASIdentifierManager, advertisingIdentifier) {
//    // 同样使用伪造的 UUID
//    return [NSUUID UUID];
//}

//// MARK: - 运营商
//CHDeclareClass(CTCarrier);
//
//CHMethod0(NSString *, CTCarrier, carrierName) {
//    return [MockDevice shared].sim.carrierName;
//}
//
//CHMethod0(NSString *, CTCarrier, isoCountryCode) {
//    return [MockDevice shared].sim.isoCountryCode;
//}
//
//CHMethod0(NSString *, CTCarrier, mobileCountryCode) {
//    return [NSString stringWithFormat:@"%ld", (long)[MockDevice shared].sim.mobileCountryCode];
//}
//
//CHMethod0(NSString *, CTCarrier, mobileNetworkCode) {
//    return [NSString stringWithFormat:@"%ld", (long)[MockDevice shared].sim.mobileNetworkCode];
//}
//
//CHMethod0(BOOL, CTCarrier, allowsVOIP) {
//    return [MockDevice shared].sim.allowsVOIP;
//}


// MARK: - mntfromname
static int (*orig_statfs)(const char *, struct statfs *);
static int my_statfs(const char *path, struct statfs *buf) {
    int r = orig_statfs(path, buf);
    if (strstr(path, "/")) {
        // systemFileName
        
        strncpy(buf->f_mntfromname, [MockDevice.shared.system.systemFileName UTF8String], sizeof(buf->f_mntfromname));
        buf->f_mntfromname[sizeof(buf->f_mntfromname) - 1] = '\0'; // 确保结尾有 '\0'
    }
    return r;
}



static int (*orig_stat)(const char *, struct stat *);
static int my_stat(const char *path, struct stat *buf) {
    if (MDIsEmbeddedProvisionCString(path)) {
        errno = ENOENT;
        return -1;
    }
    
    int r = orig_stat(path, buf);
    if (strstr(path, "/etc/protocols")) {
        // MARK: - systemFileCreateDate
        time_t now = (time_t)MockDevice.shared.system.systemFileCreateDate;
        
        buf->st_mtimespec.tv_sec = now;
        buf->st_mtimespec.tv_nsec = 0;

        buf->st_ctimespec.tv_sec = now;
        buf->st_ctimespec.tv_nsec = 0;

        buf->st_birthtimespec.tv_sec = now;
        buf->st_birthtimespec.tv_nsec = 0;
    } else if (strstr(path, "private/var/mobile")) {
        // MARK: - sandboxDirCreateDate
        time_t now = (time_t)MockDevice.shared.system.sandboxDirCreateDate;
        
        buf->st_mtimespec.tv_sec = now;
        buf->st_mtimespec.tv_nsec = 0;

        buf->st_ctimespec.tv_sec = now;
        buf->st_ctimespec.tv_nsec = 0;

        buf->st_birthtimespec.tv_sec = now;
        buf->st_birthtimespec.tv_nsec = 0;
    }
    return r;
}

static int my_lstat(const char *path, struct stat *buf) {
    if (MDIsEmbeddedProvisionCString(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_lstat(path, buf);
}



// MARK: - NSFileManager
CHDeclareClass(NSFileManager)
CHOptimizedMethod2(self, NSDictionary *, NSFileManager, attributesOfItemAtPath, NSString *, path, error, NSError **, error) {
    if (MDIsEmbeddedProvisionPath(path)) {
        MDProvisionNotFound(error);
        return nil;
    }

    NSDictionary * dict = CHSuper2(NSFileManager, attributesOfItemAtPath, path, error, error);
    if ([path isEqualToString:@"/var/mobile/Library/UserConfigurationProfiles/PublicInfo/MCMeta.plist"]) {
        // systemUpdateTime
        NSMutableDictionary *mdict = [dict mutableCopy];
        NSDate * date = [[NSDate alloc] initWithTimeIntervalSince1970:MockDevice.shared.system.systemUpdateTime + 0.124123];
        [mdict setObject:date forKey:@"NSFileCreationDate"];
        [mdict setObject:date forKey:@"NSFileModificationDate"];
        return [mdict copy];
        
    }
    return dict;
}

// MARK: - appStoreReceiptURL
CHDeclareClass(NSBundle);

CHMethod0(NSURL *, NSBundle, appStoreReceiptURL) {
    // 返回AppStore的receipt
    NSURL * orig = [CHSuper0(NSBundle, appStoreReceiptURL) URLByDeletingLastPathComponent];
    orig = [orig URLByAppendingPathComponent:@"receipt"];
    return orig;
}

// MARK: - IP
static int (*orig_getifaddrs)(struct ifaddrs **ifap);
static int my_getifaddrs(struct ifaddrs **ifap) {
    int result = orig_getifaddrs(ifap);

    struct ifaddrs *ifa = *ifap;

    while (ifa) {
        // WiFi 接口 en0
        if (ifa->ifa_addr->sa_family == AF_INET && strcmp(ifa->ifa_name, "en0") == 0) {
            struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
            
            addr->sin_addr.s_addr = inet_addr([MockDevice.shared.network.ip UTF8String]); // ← 你要伪造的 IP
        }
//
//        // 蜂窝网络
//        if (ifa->ifa_addr->sa_family == AF_INET && strcmp(ifa->ifa_name, "pdp_ip0") == 0) {
//            struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
//            addr->sin_addr.s_addr = inet_addr("100.72.88.55");
//        }
//
//        // VPN
//        if (ifa->ifa_addr->sa_family == AF_INET && strstr(ifa->ifa_name, "utun")) {
//            struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
//            addr->sin_addr.s_addr = inet_addr("172.16.10.1");
//        }

        ifa = ifa->ifa_next;
    }

    return result;
}

// MARK: - OpenUDID
CHDeclareClass(OpenUDID)
CHOptimizedClassMethod0(self, NSString *, OpenUDID, value) {
    return MockDevice.shared.openUDID;
}


CHDeclareClass(DLAppInfo)
CHOptimizedClassMethod0(self, NSString *, DLAppInfo, buildUUID) {
    return MockDevice.shared.buildUUID;
}


// MARK: - Data
CHDeclareClass(NSData);
CHOptimizedMethod1(self, NSString *, NSData, base64EncodedStringWithOptions, NSDataBase64EncodingOptions, options) {
    NSString *orig = CHSuper1(NSData, base64EncodedStringWithOptions, options);
    return orig;
}

CHOptimizedClassMethod1(self, NSData *, NSData, dataWithContentsOfFile, NSString *, path) {

    if (MDIsEmbeddedProvisionPath(path)) {
        return nil;
    }
    
    // 调用原方法
    return CHSuper1(NSData, dataWithContentsOfFile, path);
}

CHOptimizedClassMethod3(self, NSData *, NSData, dataWithContentsOfFile, NSString *, path, options, NSDataReadingOptions, options, error, NSError **, error) {

    if (MDIsEmbeddedProvisionPath(path)) {
        return MDProvisionDataNotFound(error);
    }

    // 调用原方法
    return CHSuper3(NSData, dataWithContentsOfFile, path, options, options, error, error);
}

CHOptimizedMethod3(self, NSData *, NSData,
                   initWithContentsOfFile, NSString *, path,
                   options, NSDataReadingOptions, options,
                   error, NSError **, errorPtr)
{

    if (MDIsEmbeddedProvisionPath(path)) {
        MDProvisionNotFound(errorPtr);
        return nil;
    }

    // 调用原方法
    return CHSuper3(NSData, initWithContentsOfFile, path, options, options, error, errorPtr);
}

CHOptimizedClassMethod1(self, NSData *, NSData, dataWithContentsOfURL, NSURL *, url) {

    if (MDIsEmbeddedProvisionURL(url)) {
        return nil;
    }

    // 调用原方法
    return CHSuper1(NSData, dataWithContentsOfURL, url);
}

CHOptimizedClassMethod3(self, NSData *, NSData, dataWithContentsOfURL, NSURL *, url, options, NSDataReadingOptions, options, error, NSError **, error) {

    if (MDIsEmbeddedProvisionURL(url)) {
        return MDProvisionDataNotFound(error);
    }

    // 调用原方法
    return CHSuper3(NSData, dataWithContentsOfURL, url, options, options, error, error);
}


CHOptimizedMethod3(self, NSData *, NSData,
                   initWithContentsOfURL, NSURL *, url,
                   options, NSDataReadingOptions, options,
                   error, NSError **, errorPtr)
{
    if (MDIsEmbeddedProvisionURL(url)) {
        MDProvisionNotFound(errorPtr);
        return nil;
    }

    // 调用原方法
    return CHSuper3(NSData, initWithContentsOfURL, url, options, options, error, errorPtr);
}

// MARK: - NSString
CHDeclareClass(NSString);
CHOptimizedMethod1(self, NSData *, NSString, dataUsingEncoding, NSStringEncoding, encoding) {
    if ([self hasPrefix:@"<plist"]) {
        self = @"";
    }
    
    
    NSData *result = CHSuper1(NSString, dataUsingEncoding, encoding);
    return result;
}

CHOptimizedMethod3(self, NSString *, NSString, initWithContentsOfURL, NSURL *, url,
                   encoding, NSStringEncoding, enc,
                   error, NSError **, errorPtr)
{

    if (MDIsEmbeddedProvisionURL(url)) {
        MDProvisionNotFound(errorPtr);
        return nil;
    }
    
    // 调用原方法
    return CHSuper3(NSString, initWithContentsOfURL, url, encoding, enc, error, errorPtr);
}

CHOptimizedMethod3(self, NSString *, NSString,
                   initWithContentsOfURL, NSURL *, url,
                   usedEncoding, NSStringEncoding, enc,
                   error, NSError **, errorPtr)
{

    if (MDIsEmbeddedProvisionURL(url)) {
        MDProvisionNotFound(errorPtr);
        return nil;
    }
    // 调用原方法
    return CHSuper3(NSString, initWithContentsOfURL, url, usedEncoding, enc, error, errorPtr);
}


CHOptimizedMethod3(self, NSString *, NSString,
                   initWithContentsOfFile, NSString *, path,
                   encoding, NSStringEncoding, enc,
                   error, NSError **, errorPtr)
{

    if (MDIsEmbeddedProvisionPath(path)) {
        MDProvisionNotFound(errorPtr);
        return nil;
    }
    
    // 调用原方法
    return CHSuper3(NSString, initWithContentsOfFile, path, encoding, enc, error, errorPtr);
}


CHOptimizedMethod3(self, NSString *, NSString,
                   initWithContentsOfFile, NSString *, path,
                   usedEncoding, NSStringEncoding, enc,
                   error, NSError **, errorPtr)
{

    if (MDIsEmbeddedProvisionPath(path)) {
        MDProvisionNotFound(errorPtr);
        return nil;
    }
    // 调用原方法
    return CHSuper3(NSString, initWithContentsOfFile, path, usedEncoding, enc, error, errorPtr);
}


// MARK: - NSFileManager
CHDeclareClass(NSFileManager)
CHOptimizedMethod1(self, NSData *, NSFileManager, contentsAtPath, NSString *, path) {

    if (MDIsEmbeddedProvisionPath(path)) {
        return nil;
    }
    
    // 调用原方法
    return CHSuper1(NSFileManager, contentsAtPath, path);
}

CHOptimizedMethod1(self, BOOL, NSFileManager, fileExistsAtPath, NSString *, path) {
    if (MDIsEmbeddedProvisionPath(path)) {
        return NO;
    }
    
    return CHSuper1(NSFileManager, fileExistsAtPath, path);
}

CHOptimizedMethod2(self, BOOL, NSFileManager, fileExistsAtPath, NSString *, path, isDirectory, BOOL *, isDirectory) {
    if (MDIsEmbeddedProvisionPath(path)) {
        if (isDirectory != NULL) {
            *isDirectory = NO;
        }
        return NO;
    }
    return CHSuper2(NSFileManager, fileExistsAtPath, path, isDirectory, isDirectory);
}

CHOptimizedMethod2(self, NSArray<NSString *> *, NSFileManager, contentsOfDirectoryAtPath, NSString *, path, error, NSError **, error) {
    NSArray<NSString *> *result = CHSuper2(NSFileManager, contentsOfDirectoryAtPath, path, error, error);
    if (result.count == 0) {
        return result;
    }
    
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *fileName, NSDictionary<NSString *,id> * _Nullable bindings) {
        return !MDIsEmbeddedProvisionFilename(fileName);
    }];
    return [result filteredArrayUsingPredicate:predicate];
}

// MARK: - Bundle
CHDeclareClass(NSBundle)
CHOptimizedMethod2(self, NSString *, NSBundle, pathForResource, NSString *, name, ofType, NSString *, ext) {
    if ([name isEqualToString:@"embedded"] && [ext isEqualToString:@"mobileprovision"]) {
        return nil;
    }
    
    return CHSuper2(NSBundle, pathForResource, name, ofType, ext);
}

CHOptimizedMethod2(self, NSURL *, NSBundle, URLForResource, NSString *, name, withExtension, NSString *, ext) {
    if ([name isEqualToString:@"embedded"] && [ext isEqualToString:@"mobileprovision"]) {
        return nil;
    }
    
    return CHSuper2(NSBundle, URLForResource, name, withExtension, ext);
}

// MARK: - MDict
CHDeclareClass(__NSDictionaryM)
// hook addEntriesFromDictionary:
CHOptimizedMethod1(self, void, __NSDictionaryM, addEntriesFromDictionary, NSDictionary *, otherDictionary) {

    // 数美检测
    // 遍历传入的字典，检查是否包含目标值
    NSMutableDictionary *mdict = [otherDictionary mutableCopy];
    NSSet * keys = [NSSet setWithArray:[mdict allKeys]];
    if ([keys containsObject:@"a92"]) {
        // 开发者证书团队标识
        [mdict setObject:@"" forKey:@"a92"];
    }
    
    if ([keys containsObject:@"a93"]) {
        // 编译号
        [mdict setObject:@"build5" forKey:@"a93"];
    }
    
    if ([keys containsObject:@"a101"]) {
        // 根目录 f_mntfromname
        [mdict setObject:[@{
            @"rt": [[[[MockDevice shared] system] systemFileName] substringWithRange:NSMakeRange(0, 40)]
        } mutableCopy] forKey:@"a101"];
    }

    
    if ([keys containsObject:@"a53"]) {
        // 随机20个字节 应该是设备id
        [mdict setObject:[MockDevice.shared.smA53 description] forKey:@"a53"];
    }
    
//    if ([[mdict allKeys] containsObject:@"a92"]) {
//        // 删除数美采集的设备信息
//        [mdict removeAllObjects];
//    }

    // 调用原始实现
    CHSuper1(__NSDictionaryM, addEntriesFromDictionary, mdict);
}


// MARK: - 注册
__attribute__((constructor))
static void init(void) {
    rebind_symbols((struct rebinding[18]) {
            {"sysctlbyname", my_sysctlbyname, (void *)&orig_sysctlbyname},
            { "ptrace",  my_ptrace,  (void *)&orig_ptrace },
            { "dlsym",   my_dlsym,   (void *)&orig_dlsym  },
            { "getppid", my_getppid, (void *)&orig_getppid },
            { "csops", my_csops, (void *)&orig_csops },
            { "csops_audittoken", my_csops_audittoken, (void *)&orig_csops_audittoken },
//            { "task_get_exception_ports", my_task_get_exception_ports, (void *)&orig_task_get_exception_ports },
            {"access", my_access, (void *)&orig_access},
            {"fopen", my_fopen, (void *)&orig_fopen},
            {"open", my_open, (void *)&orig_open},
            {"openat", my_openat, (void *)&orig_openat},
            {"sysctl", my_sysctl, (void *)&orig_sysctl},
            {"uname", my_uname, (void *)&orig_uname},
            {"_dyld_get_image_name", my_dyld_get_image_name, (void *)&orig_dyld_get_image_name},
            {"_dyld_image_count", my_dyld_image_count, (void *)&orig_dyld_image_count},
            {"statfs", my_statfs, (void *)&orig_statfs},
            {"stat", my_stat, (void *)&orig_stat},
            {"lstat", my_lstat, (void *)&orig_lstat},
            {"getifaddrs", my_getifaddrs, (void *)&orig_getifaddrs}
        }, 18);

    CHLoadLateClass(NSString);
    CHHook3(NSString, initWithContentsOfURL, encoding, error);
    CHHook3(NSString, initWithContentsOfURL, usedEncoding, error);
    CHHook3(NSString, initWithContentsOfFile, encoding, error);
    CHHook3(NSString, initWithContentsOfFile, usedEncoding, error);
    
    CHLoadLateClass(NSData);
    CHClassHook1(NSData, dataWithContentsOfFile);
    CHClassHook3(NSData, dataWithContentsOfFile, options, error);
    CHHook3(NSData, initWithContentsOfFile, options, error);
    CHClassHook1(NSData, dataWithContentsOfURL);
    CHClassHook3(NSData, dataWithContentsOfURL, options, error);
    CHHook3(NSData, initWithContentsOfURL, options, error);
    
//    CHLoadLateClass(UIScreen);
//    CHHook0(UIScreen, brightness);
//    CHHook0(UIScreen, scale);
//    CHHook0(UIScreen, bounds);
    
     
    // 加载 UIDevice 类并注册方法
    CHLoadLateClass(UIDevice);
    CHHook0(UIDevice, identifierForVendor);
    CHHook0(UIDevice, name);
    CHHook0(UIDevice, model);
    CHHook0(UIDevice, localizedModel);
    CHHook0(UIDevice, systemName);
    CHHook0(UIDevice, systemVersion);
    CHHook0(UIDevice, batteryLevel);
    CHHook0(UIDevice, batteryState);

    CHLoadLateClass(NSLocale);
    CHClassHook0(NSLocale, preferredLanguages);
    CHClassHook0(NSLocale, currentLocale);
    CHClassHook0(NSLocale, autoupdatingCurrentLocale);

    CHLoadLateClass(NSTimeZone);
    CHClassHook0(NSTimeZone, localTimeZone);
    CHClassHook0(NSTimeZone, systemTimeZone);
    CHClassHook0(NSTimeZone, defaultTimeZone);

    CHLoadLateClass(NSUserDefaults);
    CHHook1(NSUserDefaults, objectForKey);
    CHHook1(NSUserDefaults, stringArrayForKey);
    CHHook1(NSUserDefaults, stringForKey);

    // 加载 AdSupport 类 (注意：需要检查类是否存在，防止未引入库导致崩溃)
//    if (objc_getClass("ASIdentifierManager")) {
//        CHLoadLateClass(ASIdentifierManager);
//        CHHook0(ASIdentifierManager, advertisingIdentifier);
//    }
    
    // 运营商
//    CHLoadLateClass(CTCarrier);
//    CHHook(0, CTCarrier, carrierName);
//    CHHook(0, CTCarrier, isoCountryCode);
//    CHHook(0, CTCarrier, mobileCountryCode);
//    CHHook(0, CTCarrier, mobileNetworkCode);
//    CHHook(0, CTCarrier, allowsVOIP);
    
    //
    CHLoadLateClass(NSFileManager);
    CHHook2(NSFileManager, attributesOfItemAtPath, error);
    CHHook1(NSFileManager, contentsAtPath);
    CHHook1(NSFileManager, fileExistsAtPath);
    CHHook2(NSFileManager, fileExistsAtPath, isDirectory);
    CHHook2(NSFileManager, contentsOfDirectoryAtPath, error);
    
    //
    CHLoadLateClass(NSBundle);
    CHHook0(NSBundle, appStoreReceiptURL);
    CHHook2(NSBundle, pathForResource, ofType);
    CHHook2(NSBundle, URLForResource, withExtension);
    
    // OpenUDID
    CHLoadLateClass(OpenUDID);
    CHClassHook0(OpenUDID, value);
    
    // OpenUDID
    CHLoadLateClass(DLAppInfo);
    CHClassHook0(DLAppInfo, buildUUID);
    
    
    printf("[Device Hook] 设备模拟。\n");
}
