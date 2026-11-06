// Performance.mm
// FPS   : CADisplayLink callbacks per second on the main run loop.
// CPU   : sum of per-thread cpu_usage of THIS process (task_threads).
// Memory: phys_footprint (same metric Xcode shows). Public Mach APIs only.
#import "TDPerformance.h"
#import <mach/mach.h>
#import <QuartzCore/QuartzCore.h>

NSString * const TDPerformanceUpdatedNotification = @"TDPerformanceUpdatedNotification";

static double TDProcessCPU(void) {
    thread_array_t threads = NULL;
    mach_msg_type_number_t count = 0;
    if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) return 0;

    double total = 0;
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        thread_info_data_t info;
        mach_msg_type_number_t n = THREAD_INFO_MAX;
        if (thread_info(threads[i], THREAD_BASIC_INFO, (thread_info_t)info, &n) == KERN_SUCCESS) {
            thread_basic_info_t b = (thread_basic_info_t)info;
            if (!(b->flags & TH_FLAGS_IDLE))
                total += (double)b->cpu_usage / (double)TH_USAGE_SCALE * 100.0;
        }
        mach_port_deallocate(mach_task_self(), threads[i]);   // avoid port leak
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t));
    return total;
}

static double TDProcessMemoryMB(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return (double)info.phys_footprint / 1048576.0;
}

@interface TDPerformance ()
@property (nonatomic) double fps, cpu, memoryMB;
@property (nonatomic) BOOL running;
@end

@implementation TDPerformance {
    CADisplayLink *_link;
    NSTimer *_timer;
    NSInteger _frames;
    CFTimeInterval _lastSample;
}

+ (instancetype)shared {
    static TDPerformance *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TDPerformance new]; });
    return s;
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    _frames = 0;
    _lastSample = CACurrentMediaTime();
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(sample) userInfo:nil repeats:YES];
    _timer.tolerance = 0.2;                         // lets the OS coalesce wake-ups
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    [_link invalidate]; _link = nil;
    [_timer invalidate]; _timer = nil;
}

- (void)tick:(CADisplayLink *)link { _frames++; }

- (void)sample {
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = MAX(now - _lastSample, 0.001);
    self.fps = (double)_frames / dt;
    _frames = 0; _lastSample = now;
    self.cpu = TDProcessCPU();
    self.memoryMB = TDProcessMemoryMB();
    [[NSNotificationCenter defaultCenter] postNotificationName:TDPerformanceUpdatedNotification object:nil];
}

@end
