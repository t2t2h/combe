// TDCommon.h - shared constants.
#import <UIKit/UIKit.h>

#define TD_VERSION @"1.0.0"

// Feature keys (stored in settings).
FOUNDATION_EXPORT NSString * const TDFeatureFPS;
FOUNDATION_EXPORT NSString * const TDFeaturePerf;
FOUNDATION_EXPORT NSString * const TDFeatureNet;
FOUNDATION_EXPORT NSString * const TDFeatureTouch;
FOUNDATION_EXPORT NSString * const TDFeatureConsole;

// Notifications (always posted on the main thread).
FOUNDATION_EXPORT NSString * const TDSettingsChangedNotification;
FOUNDATION_EXPORT NSString * const TDPerformanceUpdatedNotification;
FOUNDATION_EXPORT NSString * const TDNetworkUpdatedNotification;
FOUNDATION_EXPORT NSString * const TDLogUpdatedNotification;
