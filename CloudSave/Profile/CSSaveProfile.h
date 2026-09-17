#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSSaveProfile : NSObject

@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSDate *generatedAt;
@property (nonatomic, assign) double confidence;
@property (nonatomic, copy) NSArray<NSString *> *includedPaths;
@property (nonatomic, copy) NSArray<NSString *> *observedPaths;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *sqliteFamilies;

- (NSDictionary *)dictionaryRepresentation;
- (nullable NSData *)JSONDataWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
