//
//  NSData+Hex.m
//  imhook
//
//  Created by ayo on 2025/10/22.
//

#import "NSData+Hex.h"

NSString * dataToHexString(NSData * data) {
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];

    if (!dataBuffer)
        return [NSString string];

    NSUInteger dataLength = [data length];
    NSMutableString *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];

    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    }

    return [NSString stringWithString:hexString];
}
