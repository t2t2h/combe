// TDFloatingMenu.h - overlay window, floating button and control panel.
#import <UIKit/UIKit.h>

/// Window that lets every touch outside our own controls fall through
/// to the host app, so the overlay never blocks the app.
@interface TDOverlayWindow : UIWindow
@end

@interface TDFloatingMenu : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL installed;
@property (nonatomic, readonly) UIView *touchHostView;
/// Returns NO when no foreground-active window scene exists yet (caller retries).
- (BOOL)install;
- (void)uninstall;
/// Re-reads settings (safe mode, HUD visibility).
- (void)refreshState;
- (void)refreshTheme;
@end
