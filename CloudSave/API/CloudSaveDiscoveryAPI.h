#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Capture a metadata baseline for the current host sandbox.
int CSDiscoveryCaptureBaseline(const char *home_directory, const char *baseline_path);

/// Generate discovery result JSON by comparing current sandbox state with the baseline.
/// Caller owns the returned string and must free it with CSDiscoveryFreeString().
char *CSDiscoveryGenerateResultJSON(const char *home_directory, const char *baseline_path);

void CSDiscoveryFreeString(char *value);

#ifdef __cplusplus
}
#endif
