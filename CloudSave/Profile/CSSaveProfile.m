#import "CSSaveProfile.h"

@implementation CSSaveProfile

- (instancetype)init {
    self = [super init];
    if (self) {
        _bundleIdentifier = @"unknown.bundle";
        _source = @"auto_discovery";
        _generatedAt = [NSDate date];
        _confidence = 0.0;
        _includedPaths = @[];
        _observedPaths = @[];
        _sqliteFamilies = @{};
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"schema": @1,
        @"bundle_id": self.bundleIdentifier ?: @"unknown.bundle",
        @"source": self.source ?: @"auto_discovery",
        @"generated_at": @((long long)(self.generatedAt.timeIntervalSince1970 * 1000.0)),
        @"confidence": @(self.confidence),
        @"files": self.includedPaths ?: @[],
        @"observed_files": self.observedPaths ?: @[],
        @"sqlite_families": self.sqliteFamilies ?: @{}
    };
}

- (NSData *)JSONDataWithError:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:[self dictionaryRepresentation]
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:error];
}

@end
