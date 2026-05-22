//
//  MockDevice.m
//  BluedInternationalDylib
//
//  Created by ayo on 2025/11/23.
//

#import "MockDevice.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

@implementation MKBattery
@end
@implementation MKCPU
@end
@implementation MKDisplay
@end
@implementation MKExtra
@end
@implementation MKHardware
@end
@implementation MKMemory
@end
@implementation MKNetwork
@end
@implementation MKSim
@end
@implementation MKSystemInfo
@end

@implementation MockDevice

+ (instancetype)shared {
    static MockDevice *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        obj = [[MockDevice alloc] init];
        [obj generate];
    });
    return obj;
}

#pragma mark - 随机函数

static NSData *random20Bytes(void) {
    uint8_t buffer[20];
    OSStatus status = SecRandomCopyBytes(kSecRandomDefault, sizeof(buffer), buffer);
    if (status != errSecSuccess) {
        return nil; // 随机生成失败（极罕见）
    }
    return [NSData dataWithBytes:buffer length:sizeof(buffer)];
}

static double rnd(double min, double max) {
    return min + ((double)arc4random() / UINT32_MAX) * (max - min);
}

static int rndi(int min, int max) {
    return min + arc4random_uniform(max - min + 1);
}

static id pick(NSArray *arr) {
    return arr[arc4random_uniform((uint32_t)arr.count)];
}

- (NSString *)sha256:(NSString *)input {
    const char *str = [input UTF8String];
    unsigned char result[CC_SHA256_DIGEST_LENGTH];

    CC_SHA256(str, (CC_LONG)strlen(str), result);

    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", result[i]];
    }
    return hash;
}

- (NSString*) md5: (NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

- (NSString *) _generateFreshOpenUDID {
    return nil;
}
#pragma mark - 随机生成

- (void)generate {

    Class clsOpenUDID = objc_getClass("OpenUDID");
    self.openUDID = [clsOpenUDID _generateFreshOpenUDID];
    
    self.idfv = [NSUUID UUID];
    self.buildUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    
    self.smA53 = random20Bytes();
    
    //
    // 机型模板（density + 分辨率 + CPU 必须一致）
    //
    NSArray *devices = @[
        @{@"code":@"iPhone12,1",@"w":@828, @"h":@1792, @"scale":@2, @"cpu":@6},
        @{@"code":@"iPhone13,2",@"w":@1170,@"h":@2532,@"scale":@3, @"cpu":@6},
        @{@"code":@"iPhone14,2",@"w":@1170,@"h":@2532,@"scale":@3, @"cpu":@6},
        @{@"code":@"iPhone15,3",@"w":@1290,@"h":@2796,@"scale":@3, @"cpu":@6},
    ];

    NSDictionary *tpl = pick(devices);

    NSString *code = tpl[@"code"];
    int width = [tpl[@"w"] intValue];
    int height = [tpl[@"h"] intValue];
    float scale = [tpl[@"scale"] floatValue];
    int cpuC = [tpl[@"cpu"] intValue];

    self.machineCode = code;

    //
    // 分配对象并填入随机数据
    //

    // battery
    self.battery = [MKBattery new];
    self.battery.batteryQuantity = rnd(0.7, 1.0);
    self.battery.batteryState = @"Full";

    // cpu
    self.cpu = [MKCPU new];
    self.cpu.cpuArch = @"ARM64";
    self.cpu.cpuCount = cpuC;

    // display
    self.display = [MKDisplay new];
    self.display.screenBrightness = rnd(0.3, 0.9);
    self.display.screenDensity = scale;
    self.display.screenWidth = width;
    self.display.screenHeight = height;

    // hardware
    self.hardware = [MKHardware new];
    self.hardware.deviceBrand = @"Apple";
    self.hardware.deviceCode = code;
    self.hardware.deviceLocalizedModel = code;
    self.hardware.deviceManufacturer = @"Apple";
    self.hardware.deviceModel = @"iPhone";
    self.hardware.deviceName = code;
    self.hardware.deviceSIMCount = rndi(1, 2);
    self.hardware.deviceSettingName = @"iPhone";
    self.hardware.deviceTurnOnTime = time(NULL) - rndi(1000, 200000);

    // extra
    self.extra = [MKExtra new];
    self.extra.channel = @"AppStore";

    // memory
    self.memory = [MKMemory new];
    self.memory.appMemorySpace = rnd(30.0, 80.0);     // 应用可用内存
    self.memory.diskSpace = rnd(80000.0, 160000.0);   // 总磁盘空间
    self.memory.freeDiskSpace = rnd(30000.0, 130000.0); // 可用磁盘空间
    self.memory.memorySpace = rnd(2000.0, 6000.0);    // 总内存
    self.memory.usedDiskSpace = rndi(10000, 80000);   // 已用磁盘空间

    // network
    self.network = [MKNetwork new];
    self.network.deviceIsUseProxy = NO;
    self.network.ip = [NSString stringWithFormat:@"192.168.%d.%d", rndi(0, 255), rndi(1, 254)];
    self.network.isVpnOpen = NO;
    self.network.isWifiOpen = YES;
    self.network.networkType = @"WIFI";
    self.network.signalStrength = rndi(-90, -40);

    // sim
    self.sim = [MKSim new];
    self.sim.allowsVOIP = YES;
    self.sim.carrierName = @"--";
    self.sim.isoCountryCode = @"--";
    self.sim.mobileCountryCode = rndi(100, 999);
    self.sim.mobileNetworkCode = rndi(1, 999);

    // system
    self.system = [MKSystemInfo new];
    self.system.isICloudAvailable = YES;
    self.system.languageCode = @"en";
    self.system.s0 = 1;
    self.system.s1 = 1;
    self.system.sandBoxDirDeviceId = rndi(10000, 999999);
    self.system.sandboxDirCreateDate = time(NULL) - rndi(10000, 300000);
    self.system.systemFileCreateDate = time(NULL) - rndi(20000, 300000);
    
    NSString * filenameId = [[self sha256:[NSString stringWithFormat:@"%f", [[NSDate new] timeIntervalSince1970]]] uppercaseString];
    self.system.systemFileName = [NSString stringWithFormat:@"com.apple.os.update-%@@/dev/disk1s1", filenameId];
    self.system.systemName = @"iOS";
    self.system.systemUpdateTime = time(NULL) - rndi(10000, 300000);
    self.system.systemVersion = pick(@[@"15.0",@"16.0",@"17.0"]);
    self.system.timeZone = @"America/New_York";
}

@end
