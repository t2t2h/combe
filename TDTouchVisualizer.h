// TDTouchVisualizer.h - draws a marker under every finger.
#import <UIKit/UIKit.h>

@interface TDTouchVisualizer : NSObject
+ (instancetype)shared;
/// The (non-interactive) view the markers are drawn into.
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, readonly) BOOL running;
- (void)start;
- (void)stop;
@end
