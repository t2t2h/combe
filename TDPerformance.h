// TDPerformance.h - FPS, CPU and memory sampling (this process only).
#import <Foundation/Foundation.h>
#import "TDCommon.h"

@interface TDPerformance : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) double fps;       // main run-loop display cadence
@property (nonatomic, readonly) double cpu;       // % of one core, summed over threads
@property (nonatomic, readonly) double memoryMB;  // phys_footprint of this process
@property (nonatomic, readonly) BOOL running;
- (void)start;
- (void)stop;
@end
