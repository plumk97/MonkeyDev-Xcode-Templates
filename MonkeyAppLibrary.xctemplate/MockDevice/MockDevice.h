//
//  MockDevice.h
//  BluedInternationalDylib
//
//  Created by ayo on 2025/11/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MKBattery : NSObject
@property (nonatomic) float batteryQuantity;
@property (nonatomic, copy) NSString *batteryState;
@end

@interface MKCPU : NSObject
@property (nonatomic, copy) NSString *cpuArch;
@property (nonatomic) NSInteger cpuCount;
@end

@interface MKDisplay : NSObject
@property (nonatomic) float screenBrightness;
@property (nonatomic) float screenDensity;
@property (nonatomic) NSInteger screenHeight;
@property (nonatomic) NSInteger screenWidth;
@end

@interface MKExtra : NSObject
@property (nonatomic, copy) NSString *channel;
@end

@interface MKHardware : NSObject
@property (nonatomic, copy) NSString *deviceBrand;
@property (nonatomic, copy) NSString *deviceCode;
@property (nonatomic, copy) NSString *deviceLocalizedModel;
@property (nonatomic, copy) NSString *deviceManufacturer;
@property (nonatomic, copy) NSString *deviceModel;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic) NSInteger deviceSIMCount;
@property (nonatomic, copy) NSString *deviceSettingName;
@property (nonatomic) NSTimeInterval deviceTurnOnTime;
@end

@interface MKMemory : NSObject
@property (nonatomic) float appMemorySpace;
@property (nonatomic) float diskSpace;
@property (nonatomic) float freeDiskSpace;
@property (nonatomic) float memorySpace;
@property (nonatomic) float usedDiskSpace;
@end

@interface MKNetwork : NSObject
@property (nonatomic) BOOL deviceIsUseProxy;
@property (nonatomic, copy) NSString *ip;
@property (nonatomic) BOOL isVpnOpen;
@property (nonatomic) BOOL isWifiOpen;
@property (nonatomic, copy) NSString *networkType;
@property (nonatomic) NSInteger signalStrength;
@end

@interface MKSim : NSObject
@property (nonatomic) BOOL allowsVOIP;
@property (nonatomic, copy) NSString *carrierName;
@property (nonatomic, copy) NSString *isoCountryCode;
@property (nonatomic) NSInteger mobileCountryCode;
@property (nonatomic) NSInteger mobileNetworkCode;
@end

@interface MKSystemInfo : NSObject
@property (nonatomic) BOOL isICloudAvailable;
@property (nonatomic, copy) NSString *languageCode;
@property (nonatomic) NSInteger s0;
@property (nonatomic) NSInteger s1;
@property (nonatomic) NSInteger sandBoxDirDeviceId;
@property (nonatomic) NSTimeInterval sandboxDirCreateDate;
@property (nonatomic) NSTimeInterval systemFileCreateDate;
@property (nonatomic, copy) NSString *systemFileName;
@property (nonatomic, copy) NSString *systemName;
@property (nonatomic) NSTimeInterval systemUpdateTime;
@property (nonatomic, copy) NSString *systemVersion;
@property (nonatomic, copy) NSString *timeZone;
@end

@interface MockDevice : NSObject

@property (nonatomic, strong) MKBattery *battery;
@property (nonatomic, strong) MKCPU *cpu;
@property (nonatomic, strong) MKDisplay *display;
@property (nonatomic, strong) MKExtra *extra;
@property (nonatomic, strong) MKHardware *hardware;
@property (nonatomic, strong) MKMemory *memory;
@property (nonatomic, strong) MKNetwork *network;
@property (nonatomic, strong) MKSim *sim;
@property (nonatomic, strong) MKSystemInfo *system;

@property (nonatomic, strong) NSString *machineCode;
@property (nonatomic, strong) NSUUID * idfv;
@property (nonatomic, copy) NSString * buildUUID;
@property (nonatomic, strong) NSString *openUDID;

@property (nonatomic, strong) NSData * smA53;

+ (instancetype)shared;

@end

NS_ASSUME_NONNULL_END
