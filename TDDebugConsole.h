// TDDebugConsole.h - in-memory ring buffer of diagnostic logs.
#import <Foundation/Foundation.h>
#import "TDCommon.h"

typedef NS_ENUM(NSInteger, TDLogLevel) {
    TDLogDebug = 0, TDLogInfo, TDLogWarning, TDLogError
};

@interface TDLogEntry : NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic) TDLogLevel level;
@property (nonatomic, copy) NSString *message;
@end

@interface TDDebugConsole : NSObject
+ (instancetype)shared;
- (void)log:(TDLogLevel)level message:(NSString *)message;
- (NSArray<TDLogEntry *> *)entries;
- (NSString *)exportText;
- (void)clear;
@end

#define TDLog(lvl, fmt, ...) \
    [[TDDebugConsole shared] log:(lvl) message:[NSString stringWithFormat:(fmt), ##__VA_ARGS__]]
