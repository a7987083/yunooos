#import "CloudSaveDiscoveryAPI.h"
#import "../Discovery/CSAutoDiscovery.h"
#include <stdlib.h>
#include <string.h>

static char *CSCopyUTF8String(NSString *value) {
    if (!value) return NULL;
    const char *utf8 = value.UTF8String;
    if (!utf8) return NULL;
    size_t length = strlen(utf8);
    char *result = (char *)malloc(length + 1);
    if (!result) return NULL;
    memcpy(result, utf8, length + 1);
    return result;
}

int CSDiscoveryCaptureBaseline(const char *home_directory, const char *baseline_path) {
    @autoreleasepool {
        if (!home_directory || !baseline_path) return 1;
        NSString *home = [NSString stringWithUTF8String:home_directory];
        NSString *path = [NSString stringWithUTF8String:baseline_path];
        CSAutoDiscovery *engine = [[CSAutoDiscovery alloc] initWithHomeDirectory:home bundleIdentifier:nil];
        NSError *error = nil;
        NSDictionary *baseline = [engine captureBaselineWithError:&error];
        if (!baseline) return 2;
        return [CSAutoDiscovery writeBaseline:baseline toURL:[NSURL fileURLWithPath:path] error:&error] ? 0 : 3;
    }
}

char *CSDiscoveryGenerateResultJSON(const char *home_directory, const char *baseline_path) {
    @autoreleasepool {
        if (!home_directory || !baseline_path) return NULL;
        NSString *home = [NSString stringWithUTF8String:home_directory];
        NSString *path = [NSString stringWithUTF8String:baseline_path];
        NSError *error = nil;
        NSDictionary *baseline = [CSAutoDiscovery readBaselineFromURL:[NSURL fileURLWithPath:path] error:&error];
        if (!baseline) return NULL;
        CSAutoDiscovery *engine = [[CSAutoDiscovery alloc] initWithHomeDirectory:home bundleIdentifier:nil];
        CSDiscoveryResult *result = [engine discoverFromBaseline:baseline error:&error];
        if (!result) return NULL;
        NSData *json = [NSJSONSerialization dataWithJSONObject:[result dictionaryRepresentation]
                                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                         error:&error];
        if (!json) return NULL;
        NSString *string = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        return CSCopyUTF8String(string);
    }
}

void CSDiscoveryFreeString(char *value) {
    free(value);
}
