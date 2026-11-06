// DebugConsole.mm
// Thread-safe ring buffer (500 entries). Notifications are coalesced to at
// most ~10 per second so heavy logging never floods the UI.
#import "TDDebugConsole.h"
#import "TDSettings.h"

static const NSUInteger kMaxEntries = 500;

@implementation TDLogEntry
@end

@implementation TDDebugConsole {
    NSMutableArray<TDLogEntry *> *_entries;
    NSDateFormatter *_fmt;
    BOOL _notifyPending;
}

+ (instancetype)shared {
    static TDDebugConsole *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TDDebugConsole new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _entries = [NSMutableArray array];
        _fmt = [NSDateFormatter new];
        _fmt.dateFormat = @"HH:mm:ss.SSS";
    }
    return self;
}

+ (NSString *)nameForLevel:(TDLogLevel)l {
    switch (l) {
        case TDLogDebug:   return @"DBG";
        case TDLogInfo:    return @"INF";
        case TDLogWarning: return @"WRN";
        case TDLogError:   return @"ERR";
    }
    return @"???";
}

- (void)log:(TDLogLevel)level message:(NSString *)message {
    if (message.length == 0) return;
    NSLog(@"[TheosDylib] %@", message);                      // visible in Console.app / Xcode
    if (![[TDSettings shared] isFeatureEnabled:TDFeatureConsole]) return;

    TDLogEntry *e = [TDLogEntry new];
    e.date = [NSDate date]; e.level = level; e.message = message;

    BOOL schedule = NO;
    @synchronized (self) {
        [_entries addObject:e];
        if (_entries.count > kMaxEntries)
            [_entries removeObjectsInRange:NSMakeRange(0, _entries.count - kMaxEntries)];
        if (!_notifyPending) { _notifyPending = YES; schedule = YES; }
    }
    if (schedule) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @synchronized (self) { self->_notifyPending = NO; }
            [[NSNotificationCenter defaultCenter] postNotificationName:TDLogUpdatedNotification object:nil];
        });
    }
}

- (NSArray<TDLogEntry *> *)entries {
    @synchronized (self) { return [_entries copy]; }
}

- (NSString *)exportText {
    NSMutableString *out = [NSMutableString string];
    @synchronized (self) {
        for (TDLogEntry *e in _entries) {
            [out appendFormat:@"%@ [%@] %@\n", [_fmt stringFromDate:e.date],
             [TDDebugConsole nameForLevel:e.level], e.message];
        }
    }
    return out;
}

- (void)clear {
    @synchronized (self) { [_entries removeAllObjects]; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TDLogUpdatedNotification object:nil];
    });
}

@end
