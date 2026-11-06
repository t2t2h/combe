// Settings.mm
// Persistent settings (own NSUserDefaults suite, so host app keys are never
// touched) and the crash-loop guard that implements automatic Safe Mode.
#import "TDSettings.h"
#import "TDCommon.h"

NSString * const TDFeatureFPS     = @"feature.fps";
NSString * const TDFeaturePerf    = @"feature.perf";
NSString * const TDFeatureNet     = @"feature.net";
NSString * const TDFeatureTouch   = @"feature.touch";
NSString * const TDFeatureConsole = @"feature.console";
NSString * const TDSettingsChangedNotification = @"TDSettingsChangedNotification";

static NSString * const kSuite   = @"com.theosdylib.settings";
static NSString * const kTheme   = @"ui.theme";
static NSString * const kAccent  = @"ui.accent";
static NSString * const kPing    = @"net.pingURL";
static NSString * const kOpacity = @"ui.opacity";
static NSString * const kSafe    = @"safe.enabled";
static NSString * const kGuardBusy    = @"guard.inProgress";
static NSString * const kGuardCrashes = @"guard.crashes";

@interface TDSettings ()
@property (nonatomic) BOOL launchSafeMode;
@end

@implementation TDSettings {
    NSUserDefaults *_d;
}

+ (instancetype)shared {
    static TDSettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TDSettings new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _d = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
        if (!_d) _d = [NSUserDefaults standardUserDefaults]; // defensive fallback
        [_d registerDefaults:@{
            TDFeatureFPS: @YES, TDFeaturePerf: @YES, TDFeatureNet: @NO,
            TDFeatureTouch: @NO, TDFeatureConsole: @YES,
            kTheme: @0, kAccent: @"#0A84FF",
            kPing: @"https://www.apple.com/library/test/success.html",
            kOpacity: @0.96, kSafe: @NO
        }];
    }
    return self;
}

- (void)notify {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TDSettingsChangedNotification object:nil];
    });
}

#pragma mark - Features
- (BOOL)isFeatureEnabled:(NSString *)key { return [_d boolForKey:key]; }
- (void)setFeature:(NSString *)key enabled:(BOOL)enabled { [_d setBool:enabled forKey:key]; [self notify]; }

#pragma mark - Properties
- (NSInteger)themeMode { return [_d integerForKey:kTheme]; }
- (void)setThemeMode:(NSInteger)v { [_d setInteger:MAX(0, MIN(2, v)) forKey:kTheme]; [self notify]; }

- (NSString *)accentHex { return [_d stringForKey:kAccent] ?: @"#0A84FF"; }
- (void)setAccentHex:(NSString *)v { [_d setObject:v forKey:kAccent]; [self notify]; }

- (NSString *)pingURL { return [_d stringForKey:kPing]; }
- (void)setPingURL:(NSString *)v { [_d setObject:v forKey:kPing]; [self notify]; }

- (CGFloat)panelOpacity { return (CGFloat)[_d doubleForKey:kOpacity]; }
- (void)setPanelOpacity:(CGFloat)v { [_d setDouble:MAX(0.5, MIN(1.0, v)) forKey:kOpacity]; }

- (BOOL)safeMode { return [_d boolForKey:kSafe]; }
- (void)setSafeMode:(BOOL)v { [_d setBool:v forKey:kSafe]; [self notify]; }

- (UIColor *)accentColor { return [TDSettings colorFromHex:self.accentHex]; }

+ (UIColor *)colorFromHex:(NSString *)hex {
    NSString *h = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                   stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    if (h.length != 6 || ![[NSScanner scannerWithString:h] scanHexInt:&rgb]) return UIColor.systemBlueColor;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

- (void)resetToDefaults {
    for (NSString *k in @[TDFeatureFPS, TDFeaturePerf, TDFeatureNet, TDFeatureTouch, TDFeatureConsole,
                          kTheme, kAccent, kPing, kOpacity, kSafe]) {
        [_d removeObjectForKey:k];
    }
    [self notify];
}

#pragma mark - Crash-loop guard
// Idea: mark "launch in progress" at start and clear it 15 s later. If the
// process dies before that (crash / watchdog), the flag is still set on the
// next launch and a counter increases. After 3 consecutive early deaths the
// UI is skipped for ONE launch, then everything returns to normal.
- (void)runLaunchGuard {
    BOOL busy = [_d boolForKey:kGuardBusy];
    NSInteger crashes = busy ? [_d integerForKey:kGuardCrashes] + 1 : 0;

    if (crashes >= 3) {
        self.launchSafeMode = YES;
        [_d setBool:NO forKey:kGuardBusy];
        [_d setInteger:0 forKey:kGuardCrashes];
        [_d synchronize];
        return;
    }
    [_d setInteger:crashes forKey:kGuardCrashes];
    [_d setBool:YES forKey:kGuardBusy];
    [_d synchronize];

    NSUserDefaults *d = _d;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [d setBool:NO forKey:kGuardBusy];
        [d setInteger:0 forKey:kGuardCrashes];
    });
}

@end
