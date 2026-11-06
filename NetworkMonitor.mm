// NetworkMonitor.mm
// Path status through Network.framework (nw_path_monitor) and latency as the
// round-trip time of a small HTTP HEAD request to a configurable URL.
// NOTE: true ICMP ping needs raw sockets, which iOS apps cannot open, so the
// value is an HTTP RTT (includes TLS on the first sample). It never talks to
// game servers unless YOU set pingURL to one you control.
#import "TDNetworkMonitor.h"
#import "TDSettings.h"
#import <Network/Network.h>
#import <QuartzCore/QuartzCore.h>
#import <ifaddrs.h>
#import <arpa/inet.h>

NSString * const TDNetworkUpdatedNotification = @"TDNetworkUpdatedNotification";

@interface TDNetworkMonitor ()
@property (nonatomic) BOOL running;
@property (nonatomic, copy) NSString *statusText, *interfaceText, *localIP, *targetHost;
@property (nonatomic) BOOL expensive, constrained, ipv4, ipv6;
@property (nonatomic) double lastPingMs, minPingMs, avgPingMs, maxPingMs;
@property (nonatomic) NSInteger sent, failed;
@end

@implementation TDNetworkMonitor {
    nw_path_monitor_t _monitor;
    dispatch_queue_t _queue;
    NSTimer *_timer;
    NSURLSession *_session;
    NSInteger _ok;
    double _sum;
}

+ (instancetype)shared {
    static TDNetworkMonitor *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TDNetworkMonitor new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _statusText = @"Not running"; _interfaceText = @"-"; _localIP = @"-"; _targetHost = @"-";
        _lastPingMs = -1;
    }
    return self;
}

- (void)notifyUI {
    [[NSNotificationCenter defaultCenter] postNotificationName:TDNetworkUpdatedNotification object:nil];
}

- (void)ensureSession {
    if (_session) return;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 5;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    cfg.waitsForConnectivity = NO;
    _session = [NSURLSession sessionWithConfiguration:cfg];
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    [self ensureSession];

    _queue = dispatch_queue_create("com.theosdylib.net", DISPATCH_QUEUE_SERIAL);
    _monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_monitor, _queue);
    __weak typeof(self) weakSelf = self;
    nw_path_monitor_set_update_handler(_monitor, ^(nw_path_t path) {
        BOOL online = nw_path_get_status(path) == nw_path_status_satisfied;
        NSString *iface = @"None";
        if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) iface = @"Wi-Fi";
        else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) iface = @"Cellular";
        else if (nw_path_uses_interface_type(path, nw_interface_type_wired)) iface = @"Wired";
        else if (nw_path_uses_interface_type(path, nw_interface_type_other)) iface = @"Other";
        BOOL exp = nw_path_is_expensive(path), con = nw_path_is_constrained(path);
        BOOL v4 = nw_path_has_ipv4(path), v6 = nw_path_has_ipv6(path);
        dispatch_async(dispatch_get_main_queue(), ^{
            TDNetworkMonitor *s = weakSelf;
            if (!s || !s.running) return;
            s.statusText = online ? @"Online" : @"Offline";
            s.interfaceText = iface;
            s.expensive = exp; s.constrained = con; s.ipv4 = v4; s.ipv6 = v6;
            [s notifyUI];
        });
    });
    nw_path_monitor_start(_monitor);

    _timer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(pingNow) userInfo:nil repeats:YES];
    _timer.tolerance = 0.5;
    [self pingNow];
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    [_timer invalidate]; _timer = nil;
    if (_monitor) { nw_path_monitor_cancel(_monitor); _monitor = nil; }
    [_session invalidateAndCancel]; _session = nil;
    self.statusText = @"Not running";
    [self notifyUI];
}

- (void)pingNow {
    NSURL *url = [NSURL URLWithString:[[TDSettings shared] pingURL] ?: @""];
    if (!url.host) { self.targetHost = @"invalid URL"; [self notifyUI]; return; }
    [self ensureSession];
    self.targetHost = url.host;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:5];
    req.HTTPMethod = @"HEAD";
    CFTimeInterval t0 = CACurrentMediaTime();
    __weak typeof(self) weakSelf = self;
    [[_session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
        double ms = (CACurrentMediaTime() - t0) * 1000.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            TDNetworkMonitor *s = weakSelf;
            if (!s) return;
            s.sent += 1;
            if (err || !resp) {
                s.failed += 1; s.lastPingMs = -1;
            } else {
                s.lastPingMs = ms;
                s->_ok += 1; s->_sum += ms;
                s.avgPingMs = s->_sum / s->_ok;
                s.minPingMs = (s->_ok == 1) ? ms : MIN(s.minPingMs, ms);
                s.maxPingMs = MAX(s.maxPingMs, ms);
            }
            s.localIP = [TDNetworkMonitor currentLocalIP];
            [s notifyUI];
        });
    }] resume];
}

// Local address of Wi-Fi (en0) or cellular (pdp_ip0). Public POSIX API.
+ (NSString *)currentLocalIP {
    NSString *result = @"-";
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return result;
    for (struct ifaddrs *a = list; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
        NSString *name = [NSString stringWithUTF8String:a->ifa_name];
        if (![name isEqualToString:@"en0"] && ![name isEqualToString:@"pdp_ip0"]) continue;
        char buf[INET_ADDRSTRLEN];
        struct sockaddr_in *sin = (struct sockaddr_in *)a->ifa_addr;
        if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) {
            result = [NSString stringWithFormat:@"%s (%@)", buf, name];
            if ([name isEqualToString:@"en0"]) break;
        }
    }
    freeifaddrs(list);
    return result;
}

@end
