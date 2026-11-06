// TDNetworkMonitor.h - path status + HTTP round-trip time.
#import <Foundation/Foundation.h>
#import "TDCommon.h"

@interface TDNetworkMonitor : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly, copy) NSString *statusText;     // Online / Offline / Not running
@property (nonatomic, readonly, copy) NSString *interfaceText;  // Wi-Fi / Cellular / ...
@property (nonatomic, readonly) BOOL expensive, constrained, ipv4, ipv6;
@property (nonatomic, readonly, copy) NSString *localIP;
@property (nonatomic, readonly) double lastPingMs;  // -1 = failed
@property (nonatomic, readonly) double minPingMs, avgPingMs, maxPingMs;
@property (nonatomic, readonly) NSInteger sent, failed;
@property (nonatomic, readonly, copy) NSString *targetHost;
- (void)start;
- (void)stop;
- (void)pingNow;
@end
