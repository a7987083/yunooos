#import <Foundation/Foundation.h>
#import "../Profile/CSSaveProfile.h"

NS_ASSUME_NONNULL_BEGIN

@interface CSFileObservation : NSObject
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, assign) long long modifiedUnixMs;
@property (nonatomic, copy, nullable) NSString *sha256;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)observationFromDictionary:(NSDictionary *)dictionary;
@end

@interface CSDiscoveryCandidate : NSObject
@property (nonatomic, strong) CSFileObservation *observation;
@property (nonatomic, assign) NSInteger score;
@property (nonatomic, copy) NSArray<NSString *> *reasons;
@property (nonatomic, copy, nullable) NSString *sqliteFamilyKey;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface CSDiscoveryResult : NSObject
@property (nonatomic, strong) CSSaveProfile *profile;
@property (nonatomic, copy) NSArray<CSDiscoveryCandidate *> *candidates;
@property (nonatomic, copy) NSArray<NSString *> *changedPaths;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface CSAutoDiscovery : NSObject

@property (nonatomic, copy, readonly) NSString *homeDirectory;
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;

- (instancetype)initWithHomeDirectory:(NSString *)homeDirectory
                     bundleIdentifier:(nullable NSString *)bundleIdentifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Lightweight sandbox inventory. It intentionally records metadata only;
/// hashes are calculated only for changed save candidates during discovery.
- (nullable NSDictionary<NSString *, CSFileObservation *> *)captureBaselineWithError:(NSError **)error;

/// Compare the current sandbox state with a previous baseline and synthesize
/// a profile. No hand-written per-game JSON is required.
- (nullable CSDiscoveryResult *)discoverFromBaseline:(NSDictionary<NSString *, CSFileObservation *> *)baseline
                                               error:(NSError **)error;

+ (BOOL)writeBaseline:(NSDictionary<NSString *, CSFileObservation *> *)baseline
                 toURL:(NSURL *)url
                 error:(NSError **)error;
+ (nullable NSDictionary<NSString *, CSFileObservation *> *)readBaselineFromURL:(NSURL *)url
                                                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
