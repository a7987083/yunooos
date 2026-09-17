#import "CSAutoDiscovery.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const CSErrorDomain = @"com.yunooos.discovery";
static const unsigned long long CSMaxScannableFileSize = 1024ULL * 1024ULL * 1024ULL;
static const NSInteger CSIncludeThreshold = 65;
static const NSInteger CSObserveThreshold = 40;

@implementation CSFileObservation
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [@{
        @"path": self.relativePath ?: @"",
        @"size": @(self.size),
        @"mtime_ms": @(self.modifiedUnixMs)
    } mutableCopy];
    if (self.sha256.length) dictionary[@"sha256"] = self.sha256;
    return dictionary;
}
+ (instancetype)observationFromDictionary:(NSDictionary *)dictionary {
    NSString *path = dictionary[@"path"];
    NSNumber *size = dictionary[@"size"];
    NSNumber *mtime = dictionary[@"mtime_ms"];
    if (![path isKindOfClass:NSString.class] || ![size isKindOfClass:NSNumber.class] || ![mtime isKindOfClass:NSNumber.class]) return nil;
    CSFileObservation *value = [CSFileObservation new];
    value.relativePath = path;
    value.size = size.unsignedLongLongValue;
    value.modifiedUnixMs = mtime.longLongValue;
    if ([dictionary[@"sha256"] isKindOfClass:NSString.class]) value.sha256 = dictionary[@"sha256"];
    return value;
}
@end

@implementation CSDiscoveryCandidate
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [@{
        @"file": [self.observation dictionaryRepresentation],
        @"score": @(self.score),
        @"reasons": self.reasons ?: @[]
    } mutableCopy];
    if (self.sqliteFamilyKey.length) dictionary[@"sqlite_family"] = self.sqliteFamilyKey;
    return dictionary;
}
@end

@implementation CSDiscoveryResult
- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:self.candidates.count];
    for (CSDiscoveryCandidate *candidate in self.candidates) [items addObject:[candidate dictionaryRepresentation]];
    return @{
        @"profile": [self.profile dictionaryRepresentation],
        @"changed_paths": self.changedPaths ?: @[],
        @"candidates": items
    };
}
@end

@interface CSAutoDiscovery ()
@property (nonatomic, copy, readwrite) NSString *homeDirectory;
@property (nonatomic, copy, readwrite) NSString *bundleIdentifier;
@end

@implementation CSAutoDiscovery

- (instancetype)initWithHomeDirectory:(NSString *)homeDirectory bundleIdentifier:(NSString *)bundleIdentifier {
    self = [super init];
    if (self) {
        _homeDirectory = [homeDirectory stringByStandardizingPath];
        _bundleIdentifier = bundleIdentifier.length ? bundleIdentifier : (NSBundle.mainBundle.bundleIdentifier ?: @"unknown.bundle");
    }
    return self;
}

- (NSDictionary<NSString *, CSFileObservation *> *)captureBaselineWithError:(NSError **)error {
    return [self scanSandboxWithError:error];
}

- (CSDiscoveryResult *)discoverFromBaseline:(NSDictionary<NSString *, CSFileObservation *> *)baseline error:(NSError **)error {
    NSDictionary<NSString *, CSFileObservation *> *current = [self scanSandboxWithError:error];
    if (!current) return nil;

    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    NSMutableDictionary<NSString *, CSDiscoveryCandidate *> *candidateMap = [NSMutableDictionary dictionary];

    [current enumerateKeysAndObjectsUsingBlock:^(NSString *path, CSFileObservation *now, BOOL *stop) {
        CSFileObservation *before = baseline[path];
        BOOL isNew = before == nil;
        BOOL metadataChanged = isNew || before.size != now.size || before.modifiedUnixMs != now.modifiedUnixMs;
        if (!metadataChanged) return;
        [changed addObject:path];
        CSDiscoveryCandidate *candidate = [self candidateForObservation:now isNew:isNew];
        candidateMap[path] = candidate;
    }];

    // Files that change together in one directory are more likely to belong to
    // the same save transaction. Give a small correlation boost.
    NSMutableDictionary<NSString *, NSMutableArray<CSDiscoveryCandidate *> *> *byParent = [NSMutableDictionary dictionary];
    for (CSDiscoveryCandidate *candidate in candidateMap.allValues) {
        NSString *parent = candidate.observation.relativePath.stringByDeletingLastPathComponent;
        if (!byParent[parent]) byParent[parent] = [NSMutableArray array];
        [byParent[parent] addObject:candidate];
    }
    [byParent enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<CSDiscoveryCandidate *> *group, BOOL *stop) {
        if (group.count < 2) return;
        for (CSDiscoveryCandidate *candidate in group) {
            candidate.score += 10;
            candidate.reasons = [candidate.reasons arrayByAddingObject:@"changed_with_siblings"];
        }
    }];

    // SQLite is a file family, not a single file. If one member changes, include
    // the main DB and any WAL/SHM/journal companions that exist in the sandbox.
    NSArray<CSDiscoveryCandidate *> *seedCandidates = candidateMap.allValues.copy;
    for (CSDiscoveryCandidate *candidate in seedCandidates) {
        NSString *family = candidate.sqliteFamilyKey;
        if (!family.length) continue;
        NSArray<NSString *> *members = [self existingSQLiteFamilyMembersForFamily:family current:current];
        for (NSString *member in members) {
            if (candidateMap[member]) continue;
            CSFileObservation *observation = current[member];
            if (!observation) continue;
            CSDiscoveryCandidate *companion = [self candidateForObservation:observation isNew:NO];
            companion.sqliteFamilyKey = family;
            companion.score = MAX(companion.score, 75);
            companion.reasons = [companion.reasons arrayByAddingObject:@"sqlite_family_companion"];
            candidateMap[member] = companion;
        }
    }

    // Calculate content hashes only for plausible save candidates. This keeps
    // the baseline scan fast on asset-heavy games while still giving us a
    // content identity for files that may enter a generated profile.
    for (CSDiscoveryCandidate *candidate in candidateMap.allValues) {
        if (candidate.score < CSObserveThreshold) continue;
        NSString *absolute = [self.homeDirectory stringByAppendingPathComponent:candidate.observation.relativePath];
        candidate.observation.sha256 = [self sha256ForPath:absolute error:nil];
    }

    NSArray<CSDiscoveryCandidate *> *sorted = [candidateMap.allValues sortedArrayUsingComparator:^NSComparisonResult(CSDiscoveryCandidate *left, CSDiscoveryCandidate *right) {
        if (left.score == right.score) return [left.observation.relativePath compare:right.observation.relativePath];
        return left.score > right.score ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray<NSString *> *included = [NSMutableArray array];
    NSMutableArray<NSString *> *observed = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *families = [NSMutableDictionary dictionary];
    double scoreTotal = 0.0;

    for (CSDiscoveryCandidate *candidate in sorted) {
        if (candidate.score >= CSIncludeThreshold) {
            [included addObject:candidate.observation.relativePath];
            scoreTotal += MIN(100, candidate.score);
        } else if (candidate.score >= CSObserveThreshold) {
            [observed addObject:candidate.observation.relativePath];
        }
        if (candidate.sqliteFamilyKey.length && candidate.score >= CSObserveThreshold) {
            if (!families[candidate.sqliteFamilyKey]) families[candidate.sqliteFamilyKey] = [NSMutableArray array];
            [families[candidate.sqliteFamilyKey] addObject:candidate.observation.relativePath];
        }
    }

    CSSaveProfile *profile = [CSSaveProfile new];
    profile.bundleIdentifier = self.bundleIdentifier;
    profile.includedPaths = included;
    profile.observedPaths = observed;
    profile.sqliteFamilies = families;
    if (included.count) {
        // One change session should never be treated as absolute certainty.
        // Repeated learning sessions will be added in v0.2.
        profile.confidence = MIN(0.89, (scoreTotal / (included.count * 100.0)) * 0.90);
    }

    CSDiscoveryResult *result = [CSDiscoveryResult new];
    result.profile = profile;
    result.candidates = sorted;
    result.changedPaths = [changed sortedArrayUsingSelector:@selector(compare:)];
    return result;
}

- (NSDictionary<NSString *, CSFileObservation *> *)scanSandboxWithError:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *roots = @[
        [self.homeDirectory stringByAppendingPathComponent:@"Documents"],
        [self.homeDirectory stringByAppendingPathComponent:@"Library"]
    ];
    NSArray<NSURLResourceKey> *keys = @[NSURLIsRegularFileKey, NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey, NSURLFileSizeKey, NSURLContentModificationDateKey];
    NSMutableDictionary<NSString *, CSFileObservation *> *result = [NSMutableDictionary dictionary];

    for (NSString *root in roots) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;
        NSDirectoryEnumerator<NSURL *> *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:root isDirectory:YES]
                                              includingPropertiesForKeys:keys
                                                                 options:0
                                                            errorHandler:^BOOL(NSURL *url, NSError *scanError) {
            return YES; // best-effort scan: inaccessible cache/vendor paths must not abort discovery
        }];
        for (NSURL *url in enumerator) {
            NSString *absolute = url.path.stringByStandardizingPath;
            if ([self shouldExcludeAbsolutePath:absolute]) {
                NSNumber *isDirectory = nil;
                [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
                if (isDirectory.boolValue) [enumerator skipDescendants];
                continue;
            }
            NSNumber *isRegular = nil, *isSymlink = nil, *size = nil;
            NSDate *modified = nil;
            [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
            [url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil];
            if (!isRegular.boolValue || isSymlink.boolValue) continue;
            [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
            if (size.unsignedLongLongValue > CSMaxScannableFileSize) continue;
            NSString *relative = [absolute substringFromIndex:MIN(absolute.length, self.homeDirectory.length)];
            if ([relative hasPrefix:@"/"]) relative = [relative substringFromIndex:1];
            if (!relative.length) continue;
            CSFileObservation *observation = [CSFileObservation new];
            observation.relativePath = relative;
            observation.size = size.unsignedLongLongValue;
            observation.modifiedUnixMs = modified ? (long long)(modified.timeIntervalSince1970 * 1000.0) : 0;
            result[relative] = observation;
        }
    }
    return result;
}

- (BOOL)shouldExcludeAbsolutePath:(NSString *)absolute {
    NSString *relative = absolute;
    if ([absolute hasPrefix:self.homeDirectory]) relative = [absolute substringFromIndex:self.homeDirectory.length];
    NSString *lower = relative.lowercaseString;
    NSArray<NSString *> *blocked = @[
        @"/library/caches/", @"/library/unitycache/", @"/library/logs/",
        @"/library/saved application state/", @"/tmp/", @"/documents/zonoe/",
        @"/library/application support/yunooos/", @"/documents/yunooos/"
    ];
    for (NSString *prefix in blocked) if ([lower hasPrefix:prefix] || [lower containsString:prefix]) return YES;
    return NO;
}

- (CSDiscoveryCandidate *)candidateForObservation:(CSFileObservation *)observation isNew:(BOOL)isNew {
    NSString *path = observation.relativePath;
    NSString *lower = path.lowercaseString;
    NSString *name = path.lastPathComponent.lowercaseString;
    NSString *ext = path.pathExtension.lowercaseString;
    NSInteger score = isNew ? 8 : 20;
    NSMutableArray<NSString *> *reasons = [NSMutableArray arrayWithObject:isNew ? @"new_file" : @"changed_file"];

    if ([lower hasPrefix:@"documents/"]) { score += 20; [reasons addObject:@"documents_location"]; }
    if ([lower hasPrefix:@"library/application support/"]) { score += 20; [reasons addObject:@"application_support_location"]; }
    if ([lower hasPrefix:@"library/preferences/"]) { score += 10; [reasons addObject:@"preferences_location"]; }

    NSDictionary<NSString *, NSNumber *> *extWeights = @{
        @"sav": @35, @"save": @35, @"sqlite": @30, @"sqlite3": @30, @"db": @30,
        @"dat": @25, @"plist": @20, @"bin": @15, @"json": @10, @"xml": @8
    };
    NSNumber *extensionWeight = extWeights[ext];
    if (extensionWeight) { score += extensionWeight.integerValue; [reasons addObject:[@"extension:" stringByAppendingString:ext]]; }

    NSDictionary<NSString *, NSNumber *> *keywords = @{
        @"save": @18, @"saved": @18, @"profile": @15, @"player": @15, @"progress": @18,
        @"world": @12, @"slot": @10, @"persistent": @12, @"userdata": @12, @"game": @5
    };
    [keywords enumerateKeysAndObjectsUsingBlock:^(NSString *keyword, NSNumber *weight, BOOL *stop) {
        if ([lower containsString:keyword]) { score += weight.integerValue; [reasons addObject:[@"keyword:" stringByAppendingString:keyword]]; }
    }];

    if (self.bundleIdentifier.length && [name containsString:self.bundleIdentifier.lowercaseString]) {
        score += 20;
        [reasons addObject:@"bundle_identifier_match"];
    }
    if ([lower containsString:@"cache"] || [lower containsString:@"temp"] || [lower containsString:@"temporary"]) {
        score -= 45; [reasons addObject:@"cache_or_temp_penalty"];
    }
    if ([ext isEqualToString:@"log"] || [ext isEqualToString:@"tmp"]) {
        score -= 55; [reasons addObject:@"volatile_extension_penalty"];
    }

    NSString *family = [self sqliteFamilyKeyForPath:path];
    if (family.length) {
        score += 25;
        [reasons addObject:@"sqlite_family"];
    }

    CSDiscoveryCandidate *candidate = [CSDiscoveryCandidate new];
    candidate.observation = observation;
    candidate.score = MAX(0, MIN(120, score));
    candidate.reasons = reasons;
    candidate.sqliteFamilyKey = family;
    return candidate;
}

- (NSString *)sqliteFamilyKeyForPath:(NSString *)path {
    NSString *lower = path.lowercaseString;
    for (NSString *suffix in @[@"-wal", @"-shm", @"-journal"]) {
        if ([lower hasSuffix:suffix]) return [path substringToIndex:path.length - suffix.length];
    }
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"sqlite"] || [ext isEqualToString:@"sqlite3"] || [ext isEqualToString:@"db"]) return path;
    return nil;
}

- (NSArray<NSString *> *)existingSQLiteFamilyMembersForFamily:(NSString *)family current:(NSDictionary<NSString *, CSFileObservation *> *)current {
    NSMutableArray<NSString *> *members = [NSMutableArray array];
    for (NSString *path in @[
        family,
        [family stringByAppendingString:@"-wal"],
        [family stringByAppendingString:@"-shm"],
        [family stringByAppendingString:@"-journal"]
    ]) if (current[path]) [members addObject:path];
    return members;
}

- (NSString *)sha256ForPath:(NSString *)path error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) {
        if (error) *error = [NSError errorWithDomain:CSErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unable to open candidate for hashing"}];
        return nil;
    }
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    @try {
        while (YES) {
            NSData *chunk = [handle readDataOfLength:1024 * 1024];
            if (!chunk.length) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    } @catch (NSException *exception) {
        [handle closeFile];
        if (error) *error = [NSError errorWithDomain:CSErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Hash read failed"}];
        return nil;
    }
    [handle closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

+ (BOOL)writeBaseline:(NSDictionary<NSString *, CSFileObservation *> *)baseline toURL:(NSURL *)url error:(NSError **)error {
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:baseline.count];
    NSArray *paths = [baseline.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *path in paths) [items addObject:[baseline[path] dictionaryRepresentation]];
    NSDictionary *root = @{@"schema": @1, @"files": items};
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (!data) return NO;
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

+ (NSDictionary<NSString *, CSFileObservation *> *)readBaselineFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"files"] isKindOfClass:NSArray.class]) return nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSDictionary *item in root[@"files"]) {
        CSFileObservation *observation = [CSFileObservation observationFromDictionary:item];
        if (observation.relativePath.length) result[observation.relativePath] = observation;
    }
    return result;
}

@end
