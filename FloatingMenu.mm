// FloatingMenu.mm
// UI layer only: overlay window, draggable floating button, HUD, and a panel
// with a sidebar (Dashboard / Performance / Network / Device / Touch /
// Console / Design / About). It reads state from the model classes and never
// contains monitoring logic itself. All UIKit calls happen on the main thread.
#import "TDFloatingMenu.h"
#import "TDCommon.h"
#import "TDSettings.h"
#import "TDPerformance.h"
#import "TDNetworkMonitor.h"
#import "TDDebugConsole.h"
#import "TDTouchVisualizer.h"
#import "TDMain.h"
#import <sys/utsname.h>

enum { kPageDashboard = 0, kPagePerformance, kPageNetwork, kPageDevice,
       kPageTouch, kPageConsole, kPageDesign, kPageAbout };

enum { kTagDot = 1001,
       kTagFPS = 2001, kTagCPU, kTagMEM, kTagThermal,
       kTagNetStatus = 2010, kTagNetIface, kTagNetLast, kTagNetMinAvgMax,
       kTagNetLoss, kTagNetIP, kTagNetFlags, kTagNetIPVer, kTagNetTarget,
       kTagConsoleText = 3001 };

#pragma mark - Helpers

static UILabel *TDMakeLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *l = [UILabel new];
    l.text = text; l.font = font; l.textColor = color; l.numberOfLines = 0;
    return l;
}

static NSString *TDThermalString(void) {
    switch ([NSProcessInfo processInfo].thermalState) {
        case NSProcessInfoThermalStateNominal:  return @"Nominal";
        case NSProcessInfoThermalStateFair:     return @"Fair";
        case NSProcessInfoThermalStateSerious:  return @"Serious";
        case NSProcessInfoThermalStateCritical: return @"Critical";
    }
    return @"Unknown";
}

static NSArray<NSString *> *TDAccentHexes(void) { return @[@"#0A84FF", @"#30D158", @"#FF9F0A", @"#FF375F", @"#BF5AF2"]; }
static NSArray<NSString *> *TDPingURLs(void) {
    return @[@"https://www.apple.com/library/test/success.html",
             @"https://1.1.1.1/",
             @"https://www.google.com/generate_204"];
}

static NSArray<NSArray<NSString *> *> *TDDeviceInfo(void) {
    UIDevice *dev = UIDevice.currentDevice;
    dev.batteryMonitoringEnabled = YES;
    struct utsname u; uname(&u);
    NSString *machine = [NSString stringWithUTF8String:u.machine];
    UIScreen *scr = UIScreen.mainScreen;
    NSProcessInfo *pi = NSProcessInfo.processInfo;

    NSString *battery = dev.batteryLevel < 0 ? @"n/a"
        : [NSString stringWithFormat:@"%.0f%%", dev.batteryLevel * 100];
    NSString *chg = @"Unknown";
    switch (dev.batteryState) {
        case UIDeviceBatteryStateUnplugged: chg = @"Unplugged"; break;
        case UIDeviceBatteryStateCharging:  chg = @"Charging"; break;
        case UIDeviceBatteryStateFull:      chg = @"Full"; break;
        default: break;
    }
    NSString *disk = @"n/a";
    NSDictionary *vals = [[NSURL fileURLWithPath:NSHomeDirectory()]
        resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeTotalCapacityKey] error:nil];
    NSNumber *free = vals[NSURLVolumeAvailableCapacityForImportantUsageKey], *total = vals[NSURLVolumeTotalCapacityKey];
    if (free && total) {
        disk = [NSString stringWithFormat:@"%@ free / %@",
                [NSByteCountFormatter stringFromByteCount:free.longLongValue countStyle:NSByteCountFormatterCountStyleFile],
                [NSByteCountFormatter stringFromByteCount:total.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
    }
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return @[
        @[@"Model ID", machine],
        @[@"System", [NSString stringWithFormat:@"%@ %@", dev.systemName, dev.systemVersion]],
        @[@"Screen", [NSString stringWithFormat:@"%.0fx%.0f @%.0fx", scr.bounds.size.width, scr.bounds.size.height, scr.scale]],
        @[@"Max refresh", [NSString stringWithFormat:@"%ld Hz", (long)scr.maximumFramesPerSecond]],
        @[@"RAM", [NSByteCountFormatter stringFromByteCount:(long long)pi.physicalMemory countStyle:NSByteCountFormatterCountStyleMemory]],
        @[@"CPU cores", [NSString stringWithFormat:@"%lu (%lu active)", (unsigned long)pi.processorCount, (unsigned long)pi.activeProcessorCount]],
        @[@"Storage", disk],
        @[@"Battery", [NSString stringWithFormat:@"%@ (%@)", battery, chg]],
        @[@"Low Power", pi.lowPowerModeEnabled ? @"On" : @"Off"],
        @[@"Thermal", TDThermalString()],
        @[@"App ID", NSBundle.mainBundle.bundleIdentifier ?: @"?"],
        @[@"App version", [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"]],
    ];
}

#pragma mark - Overlay window

@implementation TDOverlayWindow
// Touches that land on empty overlay area return nil -> they pass through to
// the host app's window underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface TDFloatingMenu () {
    TDOverlayWindow *_window;
    UIView *_touchHost;
    UIButton *_button;
    UIVisualEffectView *_hud;
    UILabel *_hudLabel;
    UIView *_panel, *_clip, *_header, *_content;
    UILabel *_titleLabel;
    UIScrollView *_sidebar;
    UIStackView *_sidebarStack;
    NSArray<NSString *> *_pageTitles;
    NSInteger _current;
    BOOL _panelOpen, _panelPlaced;
    NSMutableArray *_observers;
}
- (void)layoutOverlay;
@end

@interface TDRootViewController : UIViewController
@property (nonatomic, weak) TDFloatingMenu *menu;
@end

@implementation TDRootViewController
- (void)loadView { UIView *v = [UIView new]; v.backgroundColor = UIColor.clearColor; self.view = v; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self.menu layoutOverlay]; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

#pragma mark - TDFloatingMenu

@implementation TDFloatingMenu

+ (instancetype)shared {
    static TDFloatingMenu *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TDFloatingMenu new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pageTitles = @[@"Dashboard", @"Performance", @"Network", @"Device", @"Touch", @"Console", @"Design", @"About"];
        _observers = [NSMutableArray array];
    }
    return self;
}

- (BOOL)installed { return _window != nil; }
- (UIView *)touchHostView { return _touchHost; }
- (UIView *)rootView { return _window.rootViewController.view; }

#pragma mark Install / uninstall

- (BOOL)install {
    if (_window) return YES;
    UIWindowScene *scene = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if ([sc isKindOfClass:UIWindowScene.class] && sc.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)sc; break;
        }
    }
    if (!scene) return NO;

    _window = [[TDOverlayWindow alloc] initWithWindowScene:scene];
    _window.frame = scene.coordinateSpace.bounds;
    _window.windowLevel = UIWindowLevelAlert + 100;
    _window.backgroundColor = UIColor.clearColor;
    TDRootViewController *vc = [TDRootViewController new];
    vc.menu = self;
    _window.rootViewController = vc;
    [self buildViewsIn:vc.view];
    _window.hidden = NO;                         // visible, but never becomes key window

    [TDTouchVisualizer shared].hostView = _touchHost;
    [self refreshTheme];
    [self layoutOverlay];
    [self addObservers];
    return YES;
}

- (void)uninstall {
    for (id o in _observers) [[NSNotificationCenter defaultCenter] removeObserver:o];
    [_observers removeAllObjects];
    _window.hidden = YES;
    _window = nil;
}

- (void)addObservers {
    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    [_observers addObject:[nc addObserverForName:TDPerformanceUpdatedNotification object:nil queue:main
        usingBlock:^(NSNotification *n) {
            TDFloatingMenu *s = weakSelf; if (!s) return;
            [s refreshHUD];
            if (s->_panelOpen && s->_current == kPagePerformance) [s updatePerfLabels];
        }]];
    [_observers addObject:[nc addObserverForName:TDNetworkUpdatedNotification object:nil queue:main
        usingBlock:^(NSNotification *n) {
            TDFloatingMenu *s = weakSelf; if (!s) return;
            if (s->_panelOpen && s->_current == kPageNetwork) [s updateNetLabels];
        }]];
    [_observers addObject:[nc addObserverForName:TDLogUpdatedNotification object:nil queue:main
        usingBlock:^(NSNotification *n) { [weakSelf updateConsole]; }]];
}

#pragma mark Build views

- (void)buildViewsIn:(UIView *)root {
    UIColor *accent = [[TDSettings shared] accentColor];

    // Non-interactive layer that the touch visualizer draws into.
    _touchHost = [[UIView alloc] initWithFrame:root.bounds];
    _touchHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _touchHost.userInteractionEnabled = NO;
    [root addSubview:_touchHost];

    // HUD pill (FPS / CPU / MEM).
    _hud = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    _hud.frame = CGRectMake(12, 70, 190, 26);
    _hud.layer.cornerRadius = 13; _hud.clipsToBounds = YES; _hud.hidden = YES;
    _hudLabel = TDMakeLabel(@"", [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold], UIColor.labelColor);
    _hudLabel.numberOfLines = 1;
    _hudLabel.frame = CGRectInset(_hud.bounds, 8, 0);
    _hudLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_hud.contentView addSubview:_hudLabel];
    [_hud addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHUDPan:)]];
    [root addSubview:_hud];

    // Floating button.
    _button = [UIButton buttonWithType:UIButtonTypeCustom];
    _button.frame = CGRectMake(MAX(root.bounds.size.width - 64, 4), 180, 52, 52);
    _button.backgroundColor = accent;
    _button.tintColor = UIColor.whiteColor;
    _button.layer.cornerRadius = 26;
    _button.layer.shadowColor = UIColor.blackColor.CGColor;
    _button.layer.shadowOpacity = 0.3; _button.layer.shadowRadius = 6; _button.layer.shadowOffset = CGSizeMake(0, 3);
    [_button setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    [_button addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [_button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleButtonPan:)]];
    [root addSubview:_button];

    // Panel = shadow container (_panel) + clipped rounded content (_clip).
    _panel = [UIView new];
    _panel.hidden = YES;
    _panel.layer.shadowColor = UIColor.blackColor.CGColor;
    _panel.layer.shadowOpacity = 0.35; _panel.layer.shadowRadius = 16; _panel.layer.shadowOffset = CGSizeMake(0, 6);
    _clip = [UIView new];
    _clip.layer.cornerRadius = 18; _clip.layer.masksToBounds = YES;
    [_panel addSubview:_clip];

    _header = [UIView new];
    _titleLabel = TDMakeLabel(@"", [UIFont systemFontOfSize:16 weight:UIFontWeightBold], accent);
    _titleLabel.numberOfLines = 1;
    _titleLabel.frame = CGRectMake(14, 0, 200, 44);
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_header addSubview:_titleLabel];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = UIColor.secondaryLabelColor;
    close.frame = CGRectMake(0, 0, 44, 44);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:close];
    [_header addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelPan:)]];
    [_clip addSubview:_header];

    // Sidebar.
    _sidebar = [UIScrollView new];
    _sidebar.showsVerticalScrollIndicator = NO;
    _sidebarStack = [UIStackView new];
    _sidebarStack.axis = UILayoutConstraintAxisVertical; _sidebarStack.spacing = 4;
    _sidebarStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_sidebar addSubview:_sidebarStack];
    [NSLayoutConstraint activateConstraints:@[
        [_sidebarStack.topAnchor constraintEqualToAnchor:_sidebar.contentLayoutGuide.topAnchor constant:8],
        [_sidebarStack.bottomAnchor constraintEqualToAnchor:_sidebar.contentLayoutGuide.bottomAnchor constant:-8],
        [_sidebarStack.leadingAnchor constraintEqualToAnchor:_sidebar.contentLayoutGuide.leadingAnchor constant:6],
        [_sidebarStack.trailingAnchor constraintEqualToAnchor:_sidebar.contentLayoutGuide.trailingAnchor constant:-6],
        [_sidebarStack.widthAnchor constraintEqualToAnchor:_sidebar.frameLayoutGuide.widthAnchor constant:-12]]];
    for (NSUInteger i = 0; i < _pageTitles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:_pageTitles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 4);
        b.layer.cornerRadius = 8;
        b.tag = (NSInteger)i;
        [b.heightAnchor constraintEqualToConstant:36].active = YES;
        [b addTarget:self action:@selector(sidebarTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_sidebarStack addArrangedSubview:b];
    }
    [_clip addSubview:_sidebar];

    _content = [UIView new];
    _content.clipsToBounds = YES;
    [_clip addSubview:_content];

    [root insertSubview:_panel aboveSubview:_button];
}

#pragma mark Layout

- (void)layoutOverlay {
    if (!_window) return;
    UIView *root = [self rootView];
    CGRect b = root.bounds; UIEdgeInsets si = _window.safeAreaInsets;
    CGFloat w = MIN(b.size.width - 16, 540);
    CGFloat h = MIN(b.size.height - si.top - si.bottom - 16, 420);
    CGPoint c = _panel.center;
    if (!_panelPlaced) { c = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)); _panelPlaced = YES; }
    _panel.bounds = CGRectMake(0, 0, w, h);
    _panel.center = c;
    _clip.frame = _panel.bounds;
    _header.frame = CGRectMake(0, 0, w, 44);
    _sidebar.frame = CGRectMake(0, 44, 96, h - 44);
    _content.frame = CGRectMake(96, 44, w - 96, h - 44);
    [self clamp:_panel]; [self clamp:_button]; [self clamp:_hud];
}

- (void)clamp:(UIView *)v {
    UIView *root = [self rootView]; if (!root) return;
    CGRect b = root.bounds; UIEdgeInsets si = _window.safeAreaInsets;
    CGFloat hw = v.bounds.size.width / 2, hh = v.bounds.size.height / 2;
    CGPoint c = v.center;
    c.x = MAX(hw + 4, MIN(b.size.width - hw - 4, c.x));
    c.y = MAX(si.top + hh, MIN(b.size.height - si.bottom - hh, c.y));
    v.center = c;
}

#pragma mark Gestures

- (void)movePanTarget:(UIView *)t gesture:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:t.superview];
    t.center = CGPointMake(t.center.x + tr.x, t.center.y + tr.y);
    [g setTranslation:CGPointZero inView:t.superview];
    [self clamp:t];
}
- (void)handlePanelPan:(UIPanGestureRecognizer *)g { [self movePanTarget:_panel gesture:g]; }
- (void)handleHUDPan:(UIPanGestureRecognizer *)g   { [self movePanTarget:_hud gesture:g]; }
- (void)handleButtonPan:(UIPanGestureRecognizer *)g {
    [self movePanTarget:_button gesture:g];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGRect b = [self rootView].bounds; UIEdgeInsets si = _window.safeAreaInsets;
        CGFloat x = (_button.center.x < b.size.width / 2) ? 30 + si.left : b.size.width - 30 - si.right;
        [UIView animateWithDuration:0.2 animations:^{ self->_button.center = CGPointMake(x, self->_button.center.y); }];
    }
}

#pragma mark Panel open / close

- (void)togglePanel {
    if ([[TDSettings shared] safeMode]) { [self promptDisableSafeMode]; return; }
    [self setPanelOpen:!_panelOpen];
}
- (void)closePanel { [self setPanelOpen:NO]; }

- (void)setPanelOpen:(BOOL)open {
    if (_panelOpen == open) return;
    _panelOpen = open;
    if (open) {
        [self showPage:_current];
        _panel.hidden = NO; _panel.alpha = 0;
        _panel.transform = CGAffineTransformMakeScale(0.94, 0.94);
        [UIView animateWithDuration:0.2 animations:^{ self->_panel.alpha = 1; self->_panel.transform = CGAffineTransformIdentity; }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{ self->_panel.alpha = 0; } completion:^(BOOL f) {
            if (!self->_panelOpen) { self->_panel.hidden = YES; self->_panel.transform = CGAffineTransformIdentity; }
        }];
    }
}

- (void)promptDisableSafeMode {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Safe Mode is ON"
        message:@"All TheosDylib features are paused. Turn Safe Mode off?" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Turn off" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[TDSettings shared] setSafeMode:NO];
        [TDMain applyConfiguration];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [_window.rootViewController presentViewController:a animated:YES completion:nil];
}

#pragma mark State / theme

- (void)refreshState {
    if (!_window) return;
    BOOL safe = [[TDSettings shared] safeMode];
    if (safe && _panelOpen) [self setPanelOpen:NO];
    _button.alpha = safe ? 0.45 : 1.0;
    [_button setImage:[UIImage systemImageNamed:safe ? @"shield.lefthalf.filled" : @"slider.horizontal.3"]
             forState:UIControlStateNormal];
    [self refreshHUD];
}

- (void)refreshHUD {
    if (!_window) return;
    TDSettings *s = [TDSettings shared];
    BOOL fps = [s isFeatureEnabled:TDFeatureFPS], perf = [s isFeatureEnabled:TDFeaturePerf];
    BOOL show = !s.safeMode && (fps || perf);
    _hud.hidden = !show;
    if (!show) return;
    TDPerformance *p = [TDPerformance shared];
    NSMutableArray *parts = [NSMutableArray array];
    if (fps)  [parts addObject:[NSString stringWithFormat:@"FPS %.0f", p.fps]];
    if (perf) [parts addObject:[NSString stringWithFormat:@"CPU %.0f%%", p.cpu]];
    if (perf) [parts addObject:[NSString stringWithFormat:@"%.0fMB", p.memoryMB]];
    _hudLabel.text = [parts componentsJoinedByString:@" · "];
    CGSize sz = [_hudLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, 26)];
    CGRect f = _hud.frame; f.size.width = ceil(sz.width) + 18; _hud.frame = f;
    [self clamp:_hud];
}

- (void)refreshTheme {
    if (!_window) return;
    TDSettings *s = [TDSettings shared];
    switch (s.themeMode) {
        case 1:  _window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; break;
        case 2:  _window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight; break;
        default: _window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified; break;
    }
    UIColor *accent = s.accentColor;
    _button.backgroundColor = accent;
    _titleLabel.textColor = accent;
    _clip.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:s.panelOpacity];
    _sidebar.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:s.panelOpacity];
    [self updateSidebarSelection];
}

- (void)updateSidebarSelection {
    UIColor *accent = [[TDSettings shared] accentColor];
    for (UIView *v in _sidebarStack.arrangedSubviews) {
        if (![v isKindOfClass:UIButton.class]) continue;
        UIButton *b = (UIButton *)v;
        BOOL sel = (b.tag == _current);
        b.backgroundColor = sel ? [accent colorWithAlphaComponent:0.2] : UIColor.clearColor;
        [b setTitleColor:(sel ? accent : UIColor.labelColor) forState:UIControlStateNormal];
    }
}

#pragma mark Pages

- (void)sidebarTapped:(UIButton *)b { [self showPage:b.tag]; }

- (UIStackView *)newPageStack {
    for (UIView *v in _content.subviews) [v removeFromSuperview];
    UIScrollView *sv = [UIScrollView new];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.alwaysBounceVertical = YES;
    [_content addSubview:sv];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:_content.topAnchor],
        [sv.bottomAnchor constraintEqualToAnchor:_content.bottomAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor]]];
    UIStackView *st = [UIStackView new];
    st.axis = UILayoutConstraintAxisVertical; st.spacing = 10;
    st.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:st];
    [NSLayoutConstraint activateConstraints:@[
        [st.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:12],
        [st.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-12],
        [st.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor constant:12],
        [st.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor constant:-12],
        [st.widthAnchor constraintEqualToAnchor:sv.frameLayoutGuide.widthAnchor constant:-24]]];
    return st;
}

- (void)showPage:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)_pageTitles.count) idx = 0;
    _current = idx;
    UIStackView *st = [self newPageStack];
    switch (idx) {
        case kPageDashboard:   [self buildDashboard:st]; break;
        case kPagePerformance: [self buildPerformance:st]; break;
        case kPageNetwork:     [self buildNetwork:st]; break;
        case kPageDevice:      [self buildDevice:st]; break;
        case kPageTouch:       [self buildTouch:st]; break;
        case kPageConsole:     [self buildConsole:st]; break;
        case kPageDesign:      [self buildDesign:st]; break;
        case kPageAbout:       [self buildAbout:st]; break;
    }
    _titleLabel.text = [NSString stringWithFormat:@"TheosDylib · %@", _pageTitles[idx]];
    [self updateSidebarSelection];
}

#pragma mark Row builders

- (UILabel *)sectionTitle:(NSString *)t {
    return TDMakeLabel(t, [UIFont systemFontOfSize:15 weight:UIFontWeightBold], UIColor.labelColor);
}
- (UILabel *)note:(NSString *)t {
    return TDMakeLabel(t, [UIFont systemFontOfSize:12], UIColor.secondaryLabelColor);
}

- (UIView *)kvKey:(NSString *)k value:(NSString *)v tag:(NSInteger)tag {
    UILabel *kl = TDMakeLabel(k, [UIFont systemFontOfSize:13], UIColor.secondaryLabelColor);
    UILabel *vl = TDMakeLabel(v, [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium], UIColor.labelColor);
    vl.textAlignment = NSTextAlignmentRight; vl.tag = tag;
    [kl setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [kl setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[kl, vl]];
    row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 8; row.alignment = UIStackViewAlignmentFirstBaseline;
    return row;
}

- (UIColor *)dotColorForKey:(NSString *)key on:(BOOL)on {
    if (!on) return UIColor.systemGray3Color;
    if ([key isEqualToString:@"safe"]) return UIColor.systemRedColor;
    return [[TDSettings shared] safeMode] ? UIColor.systemOrangeColor : UIColor.systemGreenColor;
}

// One row = status dot + title + on/off switch. key "safe" controls Safe Mode.
- (UIView *)featureRowTitle:(NSString *)title key:(NSString *)key {
    TDSettings *s = [TDSettings shared];
    BOOL on = [key isEqualToString:@"safe"] ? s.safeMode : [s isFeatureEnabled:key];

    UIView *dot = [UIView new];
    dot.tag = kTagDot; dot.layer.cornerRadius = 5;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [dot.widthAnchor constraintEqualToConstant:10].active = YES;
    [dot.heightAnchor constraintEqualToConstant:10].active = YES;
    dot.backgroundColor = [self dotColorForKey:key on:on];

    UILabel *l = TDMakeLabel(title, [UIFont systemFontOfSize:14 weight:UIFontWeightMedium], UIColor.labelColor);
    UISwitch *sw = [UISwitch new];
    sw.on = on; sw.onTintColor = s.accentColor;
    sw.accessibilityIdentifier = key;
    [sw addTarget:self action:@selector(featureSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[dot, l, sw]];
    row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 10; row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (void)featureSwitchChanged:(UISwitch *)sw {
    NSString *key = sw.accessibilityIdentifier;
    TDSettings *s = [TDSettings shared];
    BOOL isSafe = [key isEqualToString:@"safe"];
    if (isSafe) s.safeMode = sw.on; else [s setFeature:key enabled:sw.on];
    TDLog(TDLogInfo, @"%@ -> %@", key, sw.on ? @"ON" : @"OFF");
    [TDMain applyConfiguration];
    [sw.superview viewWithTag:kTagDot].backgroundColor = [self dotColorForKey:key on:sw.on];
    if (isSafe && !sw.on) [self showPage:_current];   // refresh orange -> green dots
}

- (UIButton *)actionButtonTitle:(NSString *)t action:(SEL)sel {
    UIColor *accent = [[TDSettings shared] accentColor];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [b setTitleColor:accent forState:UIControlStateNormal];
    b.backgroundColor = [accent colorWithAlphaComponent:0.15];
    b.layer.cornerRadius = 10;
    [b.heightAnchor constraintEqualToConstant:38].active = YES;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)setText:(NSString *)t forTag:(NSInteger)tag {
    UILabel *l = (UILabel *)[_content viewWithTag:tag];
    if ([l isKindOfClass:UILabel.class]) l.text = t;
}

#pragma mark Page: Dashboard

- (void)buildDashboard:(UIStackView *)st {
    [st addArrangedSubview:[self sectionTitle:@"Features"]];
    [st addArrangedSubview:[self featureRowTitle:@"FPS Monitor" key:TDFeatureFPS]];
    [st addArrangedSubview:[self featureRowTitle:@"CPU & Memory Monitor" key:TDFeaturePerf]];
    [st addArrangedSubview:[self featureRowTitle:@"Network Diagnostics" key:TDFeatureNet]];
    [st addArrangedSubview:[self featureRowTitle:@"Touch Visualizer" key:TDFeatureTouch]];
    [st addArrangedSubview:[self featureRowTitle:@"Debug Console" key:TDFeatureConsole]];
    [st addArrangedSubview:[self note:@"Green dot = running, grey = off, orange = paused by Safe Mode."]];
    [st addArrangedSubview:[self sectionTitle:@"Safe Mode"]];
    [st addArrangedSubview:[self featureRowTitle:@"Pause everything" key:@"safe"]];
    [st addArrangedSubview:[self note:@"Stops all monitors and hides the panel. Tap the dimmed button to turn it back off. After 3 consecutive early crashes the UI is also skipped automatically for one launch."]];
}

#pragma mark Page: Performance

- (void)buildPerformance:(UIStackView *)st {
    [st addArrangedSubview:[self featureRowTitle:@"FPS Monitor" key:TDFeatureFPS]];
    [st addArrangedSubview:[self featureRowTitle:@"CPU & Memory Monitor" key:TDFeaturePerf]];
    [st addArrangedSubview:[self sectionTitle:@"Live values"]];
    [st addArrangedSubview:[self kvKey:@"FPS" value:@"--" tag:kTagFPS]];
    [st addArrangedSubview:[self kvKey:@"CPU (process)" value:@"--" tag:kTagCPU]];
    [st addArrangedSubview:[self kvKey:@"Memory (process)" value:@"--" tag:kTagMEM]];
    [st addArrangedSubview:[self kvKey:@"Thermal state" value:@"--" tag:kTagThermal]];
    [st addArrangedSubview:[self note:@"FPS = main run-loop display cadence. CPU can exceed 100% on multi-core devices (sum of threads)."]];
    [self updatePerfLabels];
}

- (void)updatePerfLabels {
    TDPerformance *p = [TDPerformance shared];
    BOOL r = p.running;
    [self setText:r ? [NSString stringWithFormat:@"%.1f", p.fps] : @"off" forTag:kTagFPS];
    [self setText:r ? [NSString stringWithFormat:@"%.1f %%", p.cpu] : @"off" forTag:kTagCPU];
    [self setText:r ? [NSString stringWithFormat:@"%.1f MB", p.memoryMB] : @"off" forTag:kTagMEM];
    [self setText:TDThermalString() forTag:kTagThermal];
}

#pragma mark Page: Network

- (void)buildNetwork:(UIStackView *)st {
    [st addArrangedSubview:[self featureRowTitle:@"Network Diagnostics" key:TDFeatureNet]];
    [st addArrangedSubview:[self sectionTitle:@"Connection"]];
    [st addArrangedSubview:[self kvKey:@"Status" value:@"--" tag:kTagNetStatus]];
    [st addArrangedSubview:[self kvKey:@"Interface" value:@"--" tag:kTagNetIface]];
    [st addArrangedSubview:[self kvKey:@"Local IP" value:@"--" tag:kTagNetIP]];
    [st addArrangedSubview:[self kvKey:@"IP versions" value:@"--" tag:kTagNetIPVer]];
    [st addArrangedSubview:[self kvKey:@"Flags" value:@"--" tag:kTagNetFlags]];
    [st addArrangedSubview:[self sectionTitle:@"Latency (HTTP RTT)"]];
    [st addArrangedSubview:[self kvKey:@"Target" value:@"--" tag:kTagNetTarget]];
    [st addArrangedSubview:[self kvKey:@"Last" value:@"--" tag:kTagNetLast]];
    [st addArrangedSubview:[self kvKey:@"Min / Avg / Max" value:@"--" tag:kTagNetMinAvgMax]];
    [st addArrangedSubview:[self kvKey:@"Failed" value:@"--" tag:kTagNetLoss]];
    [st addArrangedSubview:[self actionButtonTitle:@"Ping now" action:@selector(pingNow)]];
    [st addArrangedSubview:[self note:@"iOS apps cannot send ICMP ping, so this measures an HTTP HEAD round trip. Change the target in Design."]];
    [self updateNetLabels];
}

- (void)pingNow { [[TDNetworkMonitor shared] pingNow]; }

- (void)updateNetLabels {
    TDNetworkMonitor *n = [TDNetworkMonitor shared];
    [self setText:n.statusText forTag:kTagNetStatus];
    [self setText:n.interfaceText forTag:kTagNetIface];
    [self setText:n.localIP forTag:kTagNetIP];
    [self setText:[NSString stringWithFormat:@"v4 %@ · v6 %@", n.ipv4 ? @"yes" : @"no", n.ipv6 ? @"yes" : @"no"] forTag:kTagNetIPVer];
    [self setText:[NSString stringWithFormat:@"expensive %@ · low-data %@", n.expensive ? @"yes" : @"no", n.constrained ? @"yes" : @"no"] forTag:kTagNetFlags];
    [self setText:n.targetHost forTag:kTagNetTarget];
    NSString *last = n.sent == 0 ? @"--" : (n.lastPingMs < 0 ? @"timeout" : [NSString stringWithFormat:@"%.0f ms", n.lastPingMs]);
    [self setText:last forTag:kTagNetLast];
    NSInteger ok = n.sent - n.failed;
    [self setText:ok > 0 ? [NSString stringWithFormat:@"%.0f / %.0f / %.0f ms", n.minPingMs, n.avgPingMs, n.maxPingMs] : @"--" forTag:kTagNetMinAvgMax];
    [self setText:n.sent > 0 ? [NSString stringWithFormat:@"%ld / %ld (%.0f%%)", (long)n.failed, (long)n.sent, 100.0 * n.failed / n.sent] : @"--" forTag:kTagNetLoss];
}

#pragma mark Page: Device

- (void)buildDevice:(UIStackView *)st {
    [st addArrangedSubview:[self sectionTitle:@"Device & system"]];
    for (NSArray<NSString *> *pair in TDDeviceInfo())
        [st addArrangedSubview:[self kvKey:pair[0] value:pair[1] tag:0]];
    [st addArrangedSubview:[self note:@"Values are read when this page opens. Only public APIs are used."]];
}

#pragma mark Page: Touch

- (void)buildTouch:(UIStackView *)st {
    [st addArrangedSubview:[self featureRowTitle:@"Touch Visualizer" key:TDFeatureTouch]];
    [st addArrangedSubview:[self note:@"When enabled, a circle with X/Y coordinates follows every finger touching the app (multi-touch supported). Close this panel and tap anywhere to test. The app still receives every touch normally."]];
}

#pragma mark Page: Console

- (void)buildConsole:(UIStackView *)st {
    [st addArrangedSubview:[self featureRowTitle:@"Debug Console" key:TDFeatureConsole]];
    UITextView *tv = [UITextView new];
    tv.tag = kTagConsoleText; tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    tv.backgroundColor = UIColor.secondarySystemBackgroundColor;
    tv.textColor = UIColor.labelColor;
    tv.layer.cornerRadius = 8;
    [tv.heightAnchor constraintEqualToConstant:230].active = YES;
    [st addArrangedSubview:tv];
    UIStackView *btns = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self actionButtonTitle:@"Copy" action:@selector(consoleCopy)],
        [self actionButtonTitle:@"Clear" action:@selector(consoleClear)],
        [self actionButtonTitle:@"Test" action:@selector(consoleTest)]]];
    btns.axis = UILayoutConstraintAxisHorizontal; btns.spacing = 8; btns.distribution = UIStackViewDistributionFillEqually;
    [st addArrangedSubview:btns];
    [self updateConsole];
}

- (void)updateConsole {
    if (!(_panelOpen && _current == kPageConsole)) return;
    UITextView *tv = (UITextView *)[_content viewWithTag:kTagConsoleText];
    if (![tv isKindOfClass:UITextView.class]) return;
    tv.text = [[TDDebugConsole shared] exportText];
    if (tv.text.length > 0) [tv scrollRangeToVisible:NSMakeRange(tv.text.length - 1, 1)];
}
- (void)consoleCopy  { [UIPasteboard generalPasteboard].string = [[TDDebugConsole shared] exportText]; TDLog(TDLogInfo, @"Log copied to clipboard"); }
- (void)consoleClear { [[TDDebugConsole shared] clear]; }
- (void)consoleTest  {
    TDLog(TDLogDebug, @"debug sample"); TDLog(TDLogInfo, @"info sample");
    TDLog(TDLogWarning, @"warning sample"); TDLog(TDLogError, @"error sample");
}

#pragma mark Page: Design

- (void)buildDesign:(UIStackView *)st {
    TDSettings *s = [TDSettings shared];

    [st addArrangedSubview:[self sectionTitle:@"Theme"]];
    UISegmentedControl *theme = [[UISegmentedControl alloc] initWithItems:@[@"System", @"Dark", @"Light"]];
    theme.selectedSegmentIndex = s.themeMode;
    [theme addTarget:self action:@selector(themeChanged:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:theme];

    [st addArrangedSubview:[self sectionTitle:@"Accent color"]];
    UISegmentedControl *acc = [[UISegmentedControl alloc] initWithItems:@[@"Blue", @"Green", @"Orange", @"Pink", @"Purple"]];
    NSUInteger ai = [TDAccentHexes() indexOfObject:s.accentHex];
    acc.selectedSegmentIndex = (ai == NSNotFound) ? UISegmentedControlNoSegment : (NSInteger)ai;
    [acc addTarget:self action:@selector(accentChanged:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:acc];

    [st addArrangedSubview:[self sectionTitle:@"Panel opacity"]];
    UISlider *sl = [UISlider new];
    sl.minimumValue = 0.5; sl.maximumValue = 1.0; sl.value = s.panelOpacity;
    sl.minimumTrackTintColor = s.accentColor;
    [sl addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:sl];

    [st addArrangedSubview:[self sectionTitle:@"Ping target"]];
    UISegmentedControl *ping = [[UISegmentedControl alloc] initWithItems:@[@"Apple", @"Cloudflare", @"Google"]];
    NSUInteger pi = [TDPingURLs() indexOfObject:s.pingURL];
    ping.selectedSegmentIndex = (pi == NSNotFound) ? UISegmentedControlNoSegment : (NSInteger)pi;
    [ping addTarget:self action:@selector(pingTargetChanged:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:ping];

    [st addArrangedSubview:[self actionButtonTitle:@"Reset all settings" action:@selector(resetSettings)]];
}

- (void)themeChanged:(UISegmentedControl *)c { [[TDSettings shared] setThemeMode:c.selectedSegmentIndex]; [self refreshTheme]; [self showPage:_current]; }
- (void)accentChanged:(UISegmentedControl *)c {
    NSInteger i = c.selectedSegmentIndex; if (i < 0) return;
    [[TDSettings shared] setAccentHex:TDAccentHexes()[i]]; [self refreshTheme]; [self showPage:_current];
}
- (void)opacityChanged:(UISlider *)sl { [[TDSettings shared] setPanelOpacity:sl.value]; [self refreshTheme]; }
- (void)pingTargetChanged:(UISegmentedControl *)c {
    NSInteger i = c.selectedSegmentIndex; if (i < 0) return;
    [[TDSettings shared] setPingURL:TDPingURLs()[i]];
    TDLog(TDLogInfo, @"Ping target -> %@", TDPingURLs()[i]);
}
- (void)resetSettings {
    [[TDSettings shared] resetToDefaults];
    [TDMain applyConfiguration]; [self refreshTheme]; [self showPage:_current];
    TDLog(TDLogInfo, @"Settings reset");
}

#pragma mark Page: About

- (void)buildAbout:(UIStackView *)st {
    [st addArrangedSubview:[self sectionTitle:[NSString stringWithFormat:@"TheosDylib %@", TD_VERSION]]];
    [st addArrangedSubview:[self note:@"A diagnostics overlay for apps you own or are authorized to test: FPS, CPU/memory, network latency, device info, touch visualizer, debug console, persistent settings and Safe Mode."]];
    [st addArrangedSubview:[self sectionTitle:@"What it does NOT do"]];
    [st addArrangedSubview:[self note:@"It does not modify game logic, memory, scores, player data or server traffic, and it does not try to bypass any protection or anti-cheat. Only public Apple APIs are used."]];
    [st addArrangedSubview:[self kvKey:@"Host app" value:NSBundle.mainBundle.bundleIdentifier ?: @"?" tag:0]];
    [st addArrangedSubview:[self kvKey:@"Safe Mode" value:[[TDSettings shared] safeMode] ? @"ON" : @"OFF" tag:0]];
}

@end
