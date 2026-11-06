// TDMain.h - bootstrap and feature orchestration.
#import <Foundation/Foundation.h>

@interface TDMain : NSObject
/// Called once from the dylib constructor. Runs the crash-loop guard,
/// then installs the overlay when an active window scene exists.
+ (void)bootstrap;
/// Starts/stops every monitor according to current settings (main thread safe).
+ (void)applyConfiguration;
@end
