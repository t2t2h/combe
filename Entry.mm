// Entry.mm
// Plain C constructor: dyld runs it automatically when the dylib is loaded.
// No Logos, no Theos, no CydiaSubstrate/ElleKit: nothing is hooked, and the
// only runtime dependencies are Apple system frameworks.
#import "TDMain.h"

__attribute__((constructor))
static void TDEntryPoint(void) {
    @autoreleasepool {
        [TDMain bootstrap];   // defers UI work until a window scene exists
    }
}
