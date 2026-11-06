// TDSettings.h - persistent settings + crash-loop guard.
#import <UIKit/UIKit.h>
#import "TDCommon.h"

@interface TDSettings : NSObject
+ (instancetype)shared;

- (BOOL)isFeatureEnabled:(NSString *)key;
- (void)setFeature:(NSString *)key enabled:(BOOL)enabled;

/// 0 = follow system, 1 = dark, 2 = light.
@property (nonatomic) NSInteger themeMode;
/// Accent color as "#RRGGBB".
@property (nonatomic, copy) NSString *accentHex;
/// URL used for the HTTP round-trip measurement.
@property (nonatomic, copy) NSString *pingURL;
/// Panel background opacity 0.5 ... 1.0.
@property (nonatomic) CGFloat panelOpacity;
/// User-controlled Safe Mode (pauses all features, UI stays minimal).
@property (nonatomic) BOOL safeMode;
/// YES when the crash-loop guard disabled the UI for this launch only.
@property (nonatomic, readonly) BOOL launchSafeMode;

- (UIColor *)accentColor;
+ (UIColor *)colorFromHex:(NSString *)hex;
- (void)resetToDefaults;

/// Detects repeated early crashes (3 in a row) and enables launch safe mode.
- (void)runLaunchGuard;
@end
