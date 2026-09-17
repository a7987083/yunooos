#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Temporary standalone debug UI for exercising CloudSave AutoDiscovery.
/// This module is deliberately isolated from CloudSaveCore and can be removed later.
@interface CSH5GGDebugUI : NSObject
+ (instancetype)sharedUI;
- (void)start;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
