// TouchVisualizer.mm
// Observes touches by wrapping the PUBLIC method -[UIWindow sendEvent:]
// (original implementation is always called first, so the app's behavior is
// unchanged). Markers are drawn in the overlay's non-interactive host view.
#import "TDTouchVisualizer.h"
#import "TDSettings.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface TDTouchVisualizer ()
@property (nonatomic) BOOL running;
- (void)observeEvent:(UIEvent *)event window:(UIWindow *)window;
@end

typedef void (*TDSendEventIMP)(id, SEL, UIEvent *);
static TDSendEventIMP gOriginalSendEvent = NULL;

static void TDSendEventWrapper(UIWindow *window, SEL sel, UIEvent *event) {
    if (gOriginalSendEvent) gOriginalSendEvent(window, sel, event);   // app first
    [[TDTouchVisualizer shared] observeEvent:event window:window];
}

@implementation TDTouchVisualizer {
    NSMutableDictionary<NSNumber *, CAShapeLayer *> *_layers;
}

+ (instancetype)shared {
    static TDTouchVisualizer *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TDTouchVisualizer new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) { _layers = [NSMutableDictionary dictionary]; }
    return self;
}

- (void)start {
    if (self.running) return;
    static dispatch_once_t swizzleOnce;
    dispatch_once(&swizzleOnce, ^{
        Method m = class_getInstanceMethod([UIWindow class], @selector(sendEvent:));
        if (m) {
            gOriginalSendEvent = (TDSendEventIMP)method_getImplementation(m);
            method_setImplementation(m, (IMP)TDSendEventWrapper);
        }
    });
    self.running = YES;       // wrapper stays installed but is inert when stopped
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    for (CAShapeLayer *l in _layers.allValues) [l removeFromSuperlayer];
    [_layers removeAllObjects];
}

- (void)observeEvent:(UIEvent *)event window:(UIWindow *)window {
    if (!self.running || event.type != UIEventTypeTouches) return;
    UIView *host = self.hostView;
    UIWindow *hostWindow = host.window;
    if (!host || !hostWindow || window == hostWindow) return;   // ignore our own overlay

    for (UITouch *t in event.allTouches) {
        if (!t.window) continue;
        NSNumber *key = @((uintptr_t)(__bridge void *)t);
        CGPoint p = [t locationInView:nil];                      // window coordinates
        p = [t.window convertPoint:p toWindow:hostWindow];
        p = [host convertPoint:p fromView:nil];
        switch (t.phase) {
            case UITouchPhaseBegan:
            case UITouchPhaseMoved:
            case UITouchPhaseStationary:
                [self showAt:p key:key]; break;
            case UITouchPhaseEnded:
            case UITouchPhaseCancelled:
                [self endKey:key]; break;
            default: break;
        }
    }
}

- (void)showAt:(CGPoint)p key:(NSNumber *)key {
    UIView *host = self.hostView;
    CAShapeLayer *layer = _layers[key];
    if (!layer) {
        layer = [CAShapeLayer layer];
        layer.bounds = CGRectMake(0, 0, 48, 48);
        layer.path = [UIBezierPath bezierPathWithOvalInRect:layer.bounds].CGPath;
        UIColor *accent = [[TDSettings shared] accentColor];
        layer.fillColor = [accent colorWithAlphaComponent:0.35].CGColor;
        layer.strokeColor = accent.CGColor;
        layer.lineWidth = 2;

        CATextLayer *text = [CATextLayer layer];
        text.name = @"coords";
        text.fontSize = 10;
        text.alignmentMode = kCAAlignmentCenter;
        text.foregroundColor = UIColor.whiteColor.CGColor;
        text.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6].CGColor;
        text.cornerRadius = 4;
        text.contentsScale = UIScreen.mainScreen.scale;
        text.frame = CGRectMake(-8, 52, 64, 14);
        [layer addSublayer:text];

        [host.layer addSublayer:layer];
        _layers[key] = layer;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.position = p;
    for (CALayer *sub in layer.sublayers) {
        if ([sub.name isEqualToString:@"coords"])
            ((CATextLayer *)sub).string = [NSString stringWithFormat:@"%.0f, %.0f", p.x, p.y];
    }
    [CATransaction commit];
}

- (void)endKey:(NSNumber *)key {
    CAShapeLayer *layer = _layers[key];
    if (!layer) return;
    [_layers removeObjectForKey:key];
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.3];
    [CATransaction setCompletionBlock:^{ [layer removeFromSuperlayer]; }];
    layer.opacity = 0;
    [CATransaction commit];
}

@end
