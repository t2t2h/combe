// Main.mm
// Bootstrap + orchestration. Everything is wrapped in @try/@catch so a bug in
// this dylib can never take the host app down during startup.
#import "TDMain.h"
#import "TDSettings.h"
#import "TDDebugConsole.h"
#import "TDPerformance.h"
#import "TDNetworkMonitor.h"
#import "TDTouchVisualizer.h"
#import "TDFloatingMenu.h"

NSString * const TDLogUpdatedNotification = @"TDLogUpdatedNotification";

@implementation TDMain

+ (void)bootstrap {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            TDSettings *s = [TDSettings shared];
            [s runLaunchGuard];
            if (s.launchSafeMode) {
                NSLog(@"[TheosDylib] Crash loop detected -> UI disabled for this launch only.");
                return;
            }
            TDLog(TDLogInfo, @"TheosDylib %@ loaded into %@", TD_VERSION,
                  NSBundle.mainBundle.bundleIdentifier ?: @"?");
            dispatch_async(dispatch_get_main_queue(), ^{ [self installAttempt:0]; });
        } @catch (NSException *e) {
            NSLog(@"[TheosDylib] bootstrap exception: %@", e);
        }
    });
}

// The window scene is not ready while the app is still launching, so retry
// every 0.5 s for up to 30 s.
+ (void)installAttempt:(NSInteger)n {
    @try {
        if ([UIApplication sharedApplication] && [[TDFloatingMenu shared] install]) {
            [self applyConfiguration];
            TDLog(TDLogInfo, @"Overlay installed (attempt %ld)", (long)n + 1);
            return;
        }
    } @catch (NSException *e) {
        TDLog(TDLogError, @"install exception: %@", e);
        return;
    }
    if (n >= 60) { TDLog(TDLogError, @"No active window scene found; overlay not installed."); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self installAttempt:n + 1]; });
}

+ (void)applyConfiguration {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self applyConfiguration]; });
        return;
    }
    @try {
        TDSettings *s = [TDSettings shared];
        BOOL safe = s.safeMode || s.launchSafeMode;
        BOOL fps = [s isFeatureEnabled:TDFeatureFPS];
        BOOL perf = [s isFeatureEnabled:TDFeaturePerf];

        if (!safe && (fps || perf)) [[TDPerformance shared] start]; else [[TDPerformance shared] stop];
        if (!safe && [s isFeatureEnabled:TDFeatureNet])   [[TDNetworkMonitor shared] start]; else [[TDNetworkMonitor shared] stop];
        if (!safe && [s isFeatureEnabled:TDFeatureTouch]) [[TDTouchVisualizer shared] start]; else [[TDTouchVisualizer shared] stop];

        [[TDFloatingMenu shared] refreshState];
    } @catch (NSException *e) {
        NSLog(@"[TheosDylib] applyConfiguration exception: %@", e);
    }
}

@end
