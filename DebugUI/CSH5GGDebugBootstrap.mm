#import "CSH5GGDebugUI.h"
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void CSH5GGDebugBootstrap(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CSH5GGDebugUI sharedUI] start];
    });
}
