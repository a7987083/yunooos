#import "CSH5GGDebugUI.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../CloudSave/API/CloudSaveDiscoveryAPI.h"

@interface CSDebugPassThroughWindow : UIWindow
@end

@implementation CSDebugPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

@interface CSDebugRootViewController : UIViewController
@end

@implementation CSDebugRootViewController
- (void)loadView {
    UIView *view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = NO;
    self.view = view;
}
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

@interface CSDebugFloatButton : UIControl
@property(nonatomic) CGPoint panStartCenter;
@end

@implementation CSDebugFloatButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        self.layer.cornerRadius = CGRectGetWidth(frame) / 2.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        self.layer.shadowOpacity = 0.35;
        self.layer.shadowRadius = 8.0;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.clipsToBounds = NO;

        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.text = @"YS";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont boldSystemFontOfSize:16.0];
        label.userInteractionEnabled = NO;
        [self addSubview:label];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *container = self.superview;
    if (!container) return;
    if (pan.state == UIGestureRecognizerStateBegan) self.panStartCenter = self.center;
    CGPoint translation = [pan translationInView:container];
    CGPoint next = CGPointMake(self.panStartCenter.x + translation.x, self.panStartCenter.y + translation.y);
    CGFloat halfW = CGRectGetWidth(self.bounds) / 2.0;
    CGFloat halfH = CGRectGetHeight(self.bounds) / 2.0;
    next.x = MAX(halfW + 4.0, MIN(CGRectGetWidth(container.bounds) - halfW - 4.0, next.x));
    next.y = MAX(halfH + 4.0, MIN(CGRectGetHeight(container.bounds) - halfH - 4.0, next.y));
    self.center = next;
}
@end

@interface CSH5GGDebugUI ()
@property(nonatomic, strong) CSDebugPassThroughWindow *overlayWindow;
@property(nonatomic, strong) CSDebugFloatButton *floatButton;
@property(nonatomic, strong) UIView *menuPanel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UITextView *resultView;
@property(nonatomic, copy) NSString *lastResultJSON;
@property(nonatomic, copy) NSString *baselinePath;
@property(nonatomic) CGPoint menuPanStartCenter;
@property(nonatomic) BOOL started;
@property(nonatomic) NSInteger retryCount;
@end

@implementation CSH5GGDebugUI

+ (instancetype)sharedUI {
    static CSH5GGDebugUI *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [CSH5GGDebugUI new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/YunooosDebug"];
        _baselinePath = [dir stringByAppendingPathComponent:@"autodiscovery-baseline.json"];
    }
    return self;
}

- (UIWindow *)hostWindow {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive &&
                windowScene.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *window in windowScene.windows) {
                if (window.hidden || window.alpha <= 0.0) continue;
                if (window.windowLevel == UIWindowLevelNormal && window.rootViewController) return window;
            }
        }
    }
    UIWindow *key = app.keyWindow;
    if (key) return key;
    for (UIWindow *window in app.windows) if (!window.hidden && window.rootViewController) return window;
    return nil;
}

- (void)start {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self start]; });
        return;
    }
    if (self.started) return;

    UIWindow *host = [self hostWindow];
    if (!host) {
        if (self.retryCount++ < 30) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self start]; });
        }
        return;
    }

    self.started = YES;
    self.retryCount = 0;
    [self ensureDebugDirectory];

    CSDebugPassThroughWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        if (host.windowScene) window = [[CSDebugPassThroughWindow alloc] initWithWindowScene:host.windowScene];
    }
    if (!window) window = [[CSDebugPassThroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.frame = host.bounds;
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = UIWindowLevelAlert - 1.0;
    window.rootViewController = [CSDebugRootViewController new];
    window.hidden = NO;
    self.overlayWindow = window;

    CGFloat buttonSize = 54.0;
    CSDebugFloatButton *button = [[CSDebugFloatButton alloc] initWithFrame:CGRectMake(18.0, 110.0, buttonSize, buttonSize)];
    [button addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
    self.floatButton = button;

    [self buildMenuInWindow:window];
    self.menuPanel.hidden = YES;
    [self updateStatus:@"调试 UI 已加载 · 点击 YS 开始" busy:NO];
}

- (void)stop {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self stop]; });
        return;
    }
    [self.overlayWindow removeFromSuperview];
    self.overlayWindow.hidden = YES;
    self.overlayWindow = nil;
    self.floatButton = nil;
    self.menuPanel = nil;
    self.statusLabel = nil;
    self.resultView = nil;
    self.started = NO;
}

- (void)ensureDebugDirectory {
    NSString *dir = self.baselinePath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildMenuInWindow:(UIWindow *)window {
    CGFloat width = MIN(380.0, CGRectGetWidth(window.bounds) - 24.0);
    CGFloat height = MIN(500.0, CGRectGetHeight(window.bounds) - 50.0);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((CGRectGetWidth(window.bounds) - width) / 2.0,
                                                             (CGRectGetHeight(window.bounds) - height) / 2.0,
                                                             width, height)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                             UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    panel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.94];
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    panel.layer.shadowOpacity = 0.45;
    panel.layer.shadowRadius = 18.0;
    panel.layer.shadowOffset = CGSizeMake(0, 8);
    [window addSubview:panel];
    self.menuPanel = panel;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 52.0)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = UIColor.clearColor;
    [panel addSubview:header];
    UIPanGestureRecognizer *menuPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuPan:)];
    [header addGestureRecognizer:menuPan];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, width - 80, 24)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"Yunooos · AutoDiscovery Debug";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16.0];
    [header addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 29, width - 80, 16)];
    subtitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitle.text = @"H5GG-style temporary test menu";
    subtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.50];
    subtitle.font = [UIFont systemFontOfSize:10.5];
    [header addSubview:subtitle];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(width - 48, 8, 36, 36);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightLight];
    [close addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 54, width - 32, 38)];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.textColor = [UIColor colorWithRed:0.60 green:0.88 blue:1.0 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [panel addSubview:self.statusLabel];

    CGFloat gap = 8.0;
    CGFloat margin = 16.0;
    CGFloat buttonY = 98.0;
    CGFloat buttonW = (width - margin * 2.0 - gap) / 2.0;
    UIButton *capture = [self buttonWithTitle:@"开始学习" action:@selector(captureBaseline)];
    capture.frame = CGRectMake(margin, buttonY, buttonW, 38.0);
    [panel addSubview:capture];

    UIButton *analyze = [self buttonWithTitle:@"分析存档" action:@selector(analyzeSave)];
    analyze.frame = CGRectMake(margin + buttonW + gap, buttonY, buttonW, 38.0);
    [panel addSubview:analyze];

    UIButton *copy = [self buttonWithTitle:@"复制结果" action:@selector(copyResult)];
    copy.frame = CGRectMake(margin, buttonY + 46.0, buttonW, 38.0);
    [panel addSubview:copy];

    UIButton *reset = [self buttonWithTitle:@"清除基线" action:@selector(clearBaseline)];
    reset.frame = CGRectMake(margin + buttonW + gap, buttonY + 46.0, buttonW, 38.0);
    [panel addSubview:reset];

    CGFloat resultY = buttonY + 94.0;
    UITextView *result = [[UITextView alloc] initWithFrame:CGRectMake(margin, resultY, width - margin * 2.0, height - resultY - 16.0)];
    result.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    result.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.26];
    result.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    result.font = [UIFont fontWithName:@"Menlo" size:10.5] ?: [UIFont systemFontOfSize:10.5];
    result.layer.cornerRadius = 9.0;
    result.editable = NO;
    result.selectable = YES;
    result.text = @"使用方法：\n1. 点击「开始学习」记录当前 Sandbox 基线。\n2. 正常进入游戏并触发一次存档。\n3. 返回点击「分析存档」。\n\n菜单只用于开发验证，CloudSaveCore 不依赖它。";
    [panel addSubview:result];
    self.resultView = result;
}

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    if (!self.menuPanel.hidden) [self.overlayWindow bringSubviewToFront:self.menuPanel];
    [self.overlayWindow bringSubviewToFront:self.floatButton];
}

- (void)handleMenuPan:(UIPanGestureRecognizer *)pan {
    if (!self.menuPanel.superview) return;
    if (pan.state == UIGestureRecognizerStateBegan) self.menuPanStartCenter = self.menuPanel.center;
    CGPoint translation = [pan translationInView:self.menuPanel.superview];
    CGPoint next = CGPointMake(self.menuPanStartCenter.x + translation.x, self.menuPanStartCenter.y + translation.y);
    CGFloat halfW = CGRectGetWidth(self.menuPanel.bounds) / 2.0;
    CGFloat halfH = CGRectGetHeight(self.menuPanel.bounds) / 2.0;
    CGFloat maxX = CGRectGetWidth(self.menuPanel.superview.bounds) - halfW;
    CGFloat maxY = CGRectGetHeight(self.menuPanel.superview.bounds) - halfH;
    next.x = MAX(halfW, MIN(maxX, next.x));
    next.y = MAX(halfH, MIN(maxY, next.y));
    self.menuPanel.center = next;
}

- (void)updateStatus:(NSString *)text busy:(BOOL)busy {
    self.statusLabel.text = busy ? [@"● " stringByAppendingString:text] : text;
}

- (void)captureBaseline {
    [self ensureDebugDirectory];
    [self updateStatus:@"正在扫描 Sandbox 并建立基线…" busy:YES];
    self.resultView.text = @"正在建立基线，请正常等待扫描完成。";
    NSString *home = NSHomeDirectory();
    NSString *path = self.baselinePath;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int code = CSDiscoveryCaptureBaseline(home.fileSystemRepresentation, path.fileSystemRepresentation);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (code == 0) {
                NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
                unsigned long long bytes = [attrs[NSFileSize] unsignedLongLongValue];
                [self updateStatus:@"基线完成 · 现在进入游戏并触发一次保存" busy:NO];
                self.resultView.text = [NSString stringWithFormat:@"Baseline 已保存\n%@\nsize: %llu bytes\n\n下一步：正常游戏 → 触发一次存档 → 点击「分析存档」。", path, bytes];
            } else {
                [self updateStatus:[NSString stringWithFormat:@"建立基线失败 · code=%d", code] busy:NO];
                self.resultView.text = @"Baseline 创建失败。查看控制台日志并检查 Sandbox 访问。";
            }
        });
    });
}

- (void)analyzeSave {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.baselinePath]) {
        [self updateStatus:@"没有基线 · 请先点「开始学习」" busy:NO];
        return;
    }
    [self updateStatus:@"正在比较文件变化并评分…" busy:YES];
    NSString *home = NSHomeDirectory();
    NSString *path = self.baselinePath;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char *raw = CSDiscoveryGenerateResultJSON(home.fileSystemRepresentation, path.fileSystemRepresentation);
        NSString *json = raw ? [NSString stringWithUTF8String:raw] : nil;
        if (raw) CSDiscoveryFreeString(raw);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!json.length) {
                [self updateStatus:@"分析失败 · 未生成结果" busy:NO];
                self.resultView.text = @"AutoDiscovery 没有生成 JSON。可能是基线损坏或扫描失败。";
                return;
            }
            self.lastResultJSON = json;
            NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            self.resultView.text = [self formattedSummaryForResult:root fallback:json];
            NSDictionary *profile = [root[@"profile"] isKindOfClass:NSDictionary.class] ? root[@"profile"] : nil;
            NSArray *files = [profile[@"files"] isKindOfClass:NSArray.class] ? profile[@"files"] : @[];
            NSArray *observed = [profile[@"observed_files"] isKindOfClass:NSArray.class] ? profile[@"observed_files"] : @[];
            [self updateStatus:[NSString stringWithFormat:@"分析完成 · 高置信 %lu · 观察 %lu", (unsigned long)files.count, (unsigned long)observed.count] busy:NO];
        });
    });
}

- (NSString *)formattedSummaryForResult:(NSDictionary *)root fallback:(NSString *)fallback {
    if (![root isKindOfClass:NSDictionary.class]) return fallback ?: @"";
    NSDictionary *profile = [root[@"profile"] isKindOfClass:NSDictionary.class] ? root[@"profile"] : @{};
    NSArray *files = [profile[@"files"] isKindOfClass:NSArray.class] ? profile[@"files"] : @[];
    NSArray *observed = [profile[@"observed_files"] isKindOfClass:NSArray.class] ? profile[@"observed_files"] : @[];
    NSArray *candidates = [root[@"candidates"] isKindOfClass:NSArray.class] ? root[@"candidates"] : @[];
    NSNumber *confidence = [profile[@"confidence"] isKindOfClass:NSNumber.class] ? profile[@"confidence"] : @0;

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Bundle: %@\nConfidence: %.2f\n\n", profile[@"bundle_id"] ?: @"-", confidence.doubleValue];
    [out appendFormat:@"[自动纳入] %lu\n", (unsigned long)files.count];
    for (NSString *path in files) [out appendFormat:@"  ✓ %@\n", path];
    [out appendFormat:@"\n[继续观察] %lu\n", (unsigned long)observed.count];
    for (NSString *path in observed) [out appendFormat:@"  ? %@\n", path];
    [out appendString:@"\n[候选评分]\n"];
    NSUInteger limit = MIN((NSUInteger)40, candidates.count);
    for (NSUInteger i = 0; i < limit; i++) {
        NSDictionary *candidate = [candidates[i] isKindOfClass:NSDictionary.class] ? candidates[i] : nil;
        NSDictionary *file = [candidate[@"file"] isKindOfClass:NSDictionary.class] ? candidate[@"file"] : nil;
        [out appendFormat:@"%3ld  %@\n", (long)[candidate[@"score"] integerValue], file[@"path"] ?: @"-"];
    }
    if (candidates.count > limit) [out appendFormat:@"… 另有 %lu 个候选\n", (unsigned long)(candidates.count - limit)];
    return out;
}

- (void)copyResult {
    if (!self.lastResultJSON.length) {
        [self updateStatus:@"还没有分析结果" busy:NO];
        return;
    }
    UIPasteboard.generalPasteboard.string = self.lastResultJSON;
    [self updateStatus:@"完整 JSON 已复制到剪贴板" busy:NO];
}

- (void)clearBaseline {
    [[NSFileManager defaultManager] removeItemAtPath:self.baselinePath error:nil];
    self.lastResultJSON = nil;
    [self updateStatus:@"基线已清除" busy:NO];
    self.resultView.text = @"Baseline 已删除。点击「开始学习」重新建立。";
}

@end
