#import "TeamIdHook.h"
#import "imhook.h"

#import <Security/Security.h>

#include "../fishhook/fishhook.h"

typedef struct __SecTask *SecTaskRef;

FOUNDATION_EXPORT CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFStreamError *error);

static NSString *g_fakeTeamId = nil;
static CFTypeRef (*orig_SecTaskCopyValueForEntitlement)(SecTaskRef task, CFStringRef entitlement, CFStreamError *error);

static CFTypeRef hook_SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFStreamError *error) {
    CFTypeRef value = orig_SecTaskCopyValueForEntitlement(task, entitlement, error);

    if (g_fakeTeamId.length == 0 || entitlement == NULL) {
        return value;
    }

    if (CFEqual(entitlement, CFSTR("com.apple.developer.team-identifier"))) {
        NSLog(@"[TeamIdHook] replace team-identifier -> %@", g_fakeTeamId);
        if (value != NULL) {
            CFRelease(value);
        }
        return CFBridgingRetain(g_fakeTeamId);
    }

    if (CFEqual(entitlement, CFSTR("application-identifier"))) {
        NSString *suffix = nil;
        if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
            NSString *original = (__bridge NSString *)value;
            NSRange dotRange = [original rangeOfString:@"."];
            if (dotRange.location != NSNotFound) {
                suffix = [original substringFromIndex:dotRange.location + 1];
            }
        }

        if (suffix.length == 0) {
            suffix = [[NSBundle mainBundle] bundleIdentifier];
        }

        NSString *fakeAppId = [NSString stringWithFormat:@"%@.%@", g_fakeTeamId, suffix];
        NSLog(@"[TeamIdHook] replace application-identifier -> %@", fakeAppId);

        if (value != NULL) {
            CFRelease(value);
        }
        return CFBridgingRetain(fakeAppId);
    }

    return value;
}

void hookTeamId(NSString *teamId) {
    if (teamId.length == 0) {
        return;
    }

    g_fakeTeamId = [teamId copy];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rebind_symbols((struct rebinding[1]){
            { "SecTaskCopyValueForEntitlement", (void *)hook_SecTaskCopyValueForEntitlement, (void **)&orig_SecTaskCopyValueForEntitlement },
        }, 1);
        NSLog(@"[TeamIdHook] installed, teamId=%@", g_fakeTeamId);
    });
}
