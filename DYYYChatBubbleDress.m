//
//  DYYYChatBubbleDress.m
//  DYYY
//

#import "DYYYChatBubbleDress.h"
#import "AwemeHeaders.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"
#import <objc/runtime.h>

static NSString *const kDYYYEnableBubbleDressKey = @"DYYYEnableBubbleDress";
static NSString *const kDYYYLocalBubbleIDKey = @"DYYYLocalBubbleID";
static NSString *const kDYYYLocalBubbleNameKey = @"DYYYLocalBubbleName";
static NSString *const kDYYYObservedBubbleIDKey = @"DYYYObservedUserBubbleID";

static const CGFloat kDYYYPanelButtonWidth = 118.0;
static const CGFloat kDYYYPanelButtonHeight = 38.0;
/// 面板事件的新鲜期：超过这个时间就不再显示「本地装扮」按钮
static const NSTimeInterval kDYYYPanelEventFreshInterval = 20.0;

#pragma mark - 面板按钮

@interface DYYYLocalBubbleButton : UIButton
@end

@implementation DYYYLocalBubbleButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        self.layer.cornerRadius = kDYYYPanelButtonHeight / 2.0;
        self.layer.borderWidth = 1.0;
        [self refreshAppearance];
    }
    return self;
}

- (void)refreshAppearance {
    DYYYChatBubbleDress *dress = [DYYYChatBubbleDress sharedInstance];
    BOOL isCurrentPanelBubble = (dress.active && dress.panelBubbleID.length > 0 &&
                                 [dress.localBubbleID isEqualToString:dress.panelBubbleID]);
    // 当前装扮的就是这个气泡 → 「恢复装扮」；不是 → 「本地装扮」
    [self setTitle:(isCurrentPanelBubble ? @"恢复装扮" : @"本地装扮") forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    self.layer.borderWidth = 1.0;
    UIColor *accent = self.tintColor ?: [UIColor colorWithRed:1.0 green:0.17 blue:0.33 alpha:1.0];
    if (isCurrentPanelBubble) {
        // 已装扮成这个气泡：淡色填充 + 同色字（比纯黑更像"这套按钮里的第二颗"）
        self.backgroundColor = [accent colorWithAlphaComponent:0.16];
        self.layer.borderColor = [accent colorWithAlphaComponent:0.9].CGColor;
        [self setTitleColor:accent forState:UIControlStateNormal];
    } else {
        // 官方那颗是实心色，这颗做成白底 + 同色描边/文字 —— 并排看是一套的两颗按钮
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.96];
        self.layer.borderColor = [accent colorWithAlphaComponent:0.85].CGColor;
        [self setTitleColor:accent forState:UIControlStateNormal];
    }
}

@end

#pragma mark -

@interface DYYYChatBubbleDress ()

@property (nonatomic, strong, nullable) DYYYLocalBubbleButton *panelButton;
@property (nonatomic, weak, nullable) UIView *panelButtonContainer;
@property (nonatomic, weak, nullable) UIView *officialLabel;
@property (nonatomic, assign) CGRect originalContainerFrame;
@property (nonatomic, assign) CGRect originalLabelFrame;
@property (nonatomic, copy, nullable) NSString *panelBubbleID;
@property (nonatomic, copy, nullable) NSString *panelBubbleName;
@property (nonatomic, assign) NSTimeInterval lastPanelEventTime;
@property (nonatomic, weak, nullable) id userBubbleComponent;
@property (nonatomic, assign) NSTimeInterval lastPrefetchTime;
@property (nonatomic, assign) NSTimeInterval lastButtonRefreshTime;
@property (nonatomic, assign) NSTimeInterval lastReassertScheduleTime;

@end

@implementation DYYYChatBubbleDress

+ (instancetype)sharedInstance {
    static DYYYChatBubbleDress *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[DYYYChatBubbleDress alloc] init];
    });
    return instance;
}

#pragma mark - 状态

- (BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // 缺省视为开：只有用户主动关掉才停用（关掉后立即恢复官方气泡）
    if ([defaults objectForKey:kDYYYEnableBubbleDressKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:kDYYYEnableBubbleDressKey];
}

- (NSString *)localBubbleID {
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYLocalBubbleIDKey];
    return value.length > 0 ? value : nil;
}

- (NSString *)localBubbleName {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYLocalBubbleNameKey];
}

- (BOOL)active {
    return self.enabled && self.localBubbleID.length > 0;
}

/// "我当前的官方气泡 id"：内存里没有就用上次持久化的（重启后直接进聊天也能用）
- (NSString *)currentUserBubbleID {
    if (_currentUserBubbleID.length > 0) {
        return _currentUserBubbleID;
    }
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kDYYYObservedBubbleIDKey];
    if (saved.length > 0) {
        _currentUserBubbleID = [saved copy];
    }
    return _currentUserBubbleID;
}

#pragma mark - 抓取

- (void)handleBridgeParamModel:(id)model {
    if (!model) {
        return;
    }
    NSString *event = nil;
    id params = nil;
    @try {
        event = [model valueForKey:@"eventName"];
        params = [model valueForKey:@"params"];
    } @catch (__unused NSException *exception) {
        return;
    }
    if (![event isKindOfClass:[NSString class]] || ![event containsString:@"bubble"]) {
        return;   // 只关心气泡相关事件（bubble_redemption_page_show / _click 等）
    }
    NSString *bubbleID = nil;
    NSString *bubbleName = nil;
    @try {
        if ([params isKindOfClass:[NSDictionary class]]) {
            id rawID = ((NSDictionary *)params)[@"bubble_id"];
            id rawName = ((NSDictionary *)params)[@"bubble_name"];
            if ([rawID isKindOfClass:[NSString class]]) {
                bubbleID = rawID;
            } else if ([rawID isKindOfClass:[NSNumber class]]) {
                bubbleID = [rawID stringValue];
            }
            if ([rawName isKindOfClass:[NSString class]]) {
                bubbleName = rawName;
            }
        }
    } @catch (__unused NSException *exception) {
    }
    if (bubbleID.length == 0) {
        return;
    }
    if (bubbleName.length > 0) {
        self.panelBubbleName = bubbleName;
    }
    self.panelBubbleID = bubbleID;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    self.lastPanelEventTime = now;
    // 面板事件很频繁：按钮外观即时刷（节流 0.5 秒），并顺手重建一次 —— Lynx 重画容器时能把按钮塞回去
    BOOL shouldReassert = (now - self.lastButtonRefreshTime) > 0.5;
    if (shouldReassert) {
        self.lastButtonRefreshTime = now;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.panelButton refreshAppearance];
        if (shouldReassert) {
            [self updatePanelButtonForTopViewController];
        }
    });
}

- (BOOL)hasRecentPanelEvent {
    if (self.lastPanelEventTime <= 0) {
        return NO;
    }
    return ([NSDate date].timeIntervalSince1970 - self.lastPanelEventTime) <= kDYYYPanelEventFreshInterval;
}

#pragma mark - 应用 / 清除

- (void)applyLocalBubbleID:(NSString *)bubbleID name:(NSString *)name {
    if (bubbleID.length == 0) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:bubbleID forKey:kDYYYLocalBubbleIDKey];
    if (name.length > 0) {
        [defaults setObject:name forKey:kDYYYLocalBubbleNameKey];
    }
    [defaults synchronize];
    [self prefetchResourcesIfNeeded:YES];
}

- (void)clearLocalBubble {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kDYYYLocalBubbleIDKey];
    [defaults removeObjectForKey:kDYYYLocalBubbleNameKey];
    [defaults synchronize];
}

#pragma mark - 读取键改写

/// 记下"我当前的官方气泡 id"（`<某id>_self` 里的 id 就是它；本地气泡自己不算）
- (void)rememberObservedBubbleID:(NSString *)bubbleID {
    if (bubbleID.length == 0) {
        return;
    }
    if ([bubbleID isEqualToString:self.localBubbleID]) {
        return;   // 这是"本地气泡"的键，不是我的官方气泡
    }
    if ([bubbleID isEqualToString:self.panelBubbleID]) {
        return;   // 商店面板里正在看的那个气泡，不是"我当前的"（否则会被它顶替，颜色那条路会失准）
    }
    if ([bubbleID isEqualToString:self.currentUserBubbleID]) {
        return;
    }
    self.currentUserBubbleID = bubbleID;
    [[NSUserDefaults standardUserDefaults] setObject:bubbleID forKey:kDYYYObservedBubbleIDKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)noteBubbleKeyObserved:(id)key {
    if (![key isKindOfClass:[NSString class]]) {
        return;
    }
    NSString *keyString = (NSString *)key;
    if (![keyString hasSuffix:@"_self"]) {
        return;
    }
    [self rememberObservedBubbleID:[keyString substringToIndex:keyString.length - 5]];
}

- (NSArray<NSString *> *)rewriteCandidatesForKey:(id)key {
    if (!self.active || ![key isKindOfClass:[NSString class]]) {
        return @[];
    }
    NSString *keyString = (NSString *)key;
    NSString *mine = self.currentUserBubbleID;
    NSString *idPart = keyString;
    NSString *suffix = @"";
    if ([keyString hasSuffix:@"_self"]) {
        // "_self" 按定义就是"我这一侧"，所以这一类一律改写（这也让重启后立刻生效，
        // 不必等 AWEIMUserBubbleUtility 那个一次启动只调一次的方法）
        idPart = [keyString substringToIndex:keyString.length - 5];
        suffix = @"_self";
        [self rememberObservedBubbleID:idPart];
    } else if ([keyString hasSuffix:@"_peer"]) {
        return @[];   // 对方的气泡：绝不动
    } else {
        // 裸 id（文字颜色那条路就是这么读的）：只有等于"我当前气泡 id"才算我的
        if (mine.length == 0 || ![idPart isEqualToString:mine]) {
            return @[];
        }
    }
    if ([idPart isEqualToString:self.localBubbleID]) {
        return @[];   // 已经是本地气泡的键，不必再改写
    }
    NSString *local = self.localBubbleID;
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    void (^add)(NSString *) = ^(NSString *candidate) {
        if (candidate.length > 0 && ![list containsObject:candidate]) {
            [list addObject:candidate];
        }
    };
    add([local stringByAppendingString:suffix]);
    add([local stringByAppendingString:@"_self"]);
    add(local);
    return list;
}

#pragma mark - 资源预取

- (void)noteUserBubbleComponent:(id)component {
    if (component) {
        self.userBubbleComponent = component;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self prefetchResourcesIfNeeded:NO];
        });
        return;
    }
    [self prefetchResourcesIfNeeded:NO];
}

- (void)prefetchResourcesIfNeeded:(BOOL)force {
    if (!self.active) {
        return;
    }
    NSString *local = self.localBubbleID;
    id component = self.userBubbleComponent;
    if (local.length == 0 || !component) {
        return;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (!force && (now - self.lastPrefetchTime) < 60.0) {
        return;   // 一分钟内只补拉一次
    }
    self.lastPrefetchTime = now;
    if ([component respondsToSelector:@selector(tryRequestBubbleImageWithBubbleID:)]) {
        [component tryRequestBubbleImageWithBubbleID:local];
    }
}

#pragma mark - 面板按钮：显隐

- (UIWindow *)hostWindow {
    UIWindow *best = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        NSString *cls = NSStringFromClass([window class]);
        if (window.hidden || window.alpha < 0.01) {
            continue;
        }
        if ([cls containsString:@"TextEffects"] || [cls containsString:@"Input"]) {
            continue;   // 键盘窗口
        }
        if (!best || window.windowLevel >= best.windowLevel) {
            best = window;
        }
    }
    return best ?: [DYYYUtils getActiveWindow];
}

- (UIViewController *)topViewController {
    UIWindow *window = [self hostWindow];
    UIViewController *top = window.rootViewController ?: [DYYYUtils getActiveWindow].rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    if ([top isKindOfClass:[UINavigationController class]]) {
        UIViewController *visible = ((UINavigationController *)top).topViewController;
        if (visible) {
            top = visible;
        }
    }
    return top;
}

- (void)updatePanelButtonForTopViewController {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updatePanelButtonForTopViewController];
        });
        return;
    }
    if (!self.enabled) {
        [self hidePanelButton];
        return;
    }
    UIViewController *top = [self topViewController];
    NSString *cls = NSStringFromClass([top class]);
    BOOL panelUp = [cls containsString:@"BDXPopup"] && top.isViewLoaded;
    BOOL haveContainer = (self.panelButtonContainer && self.panelButtonContainer.superview != nil);
    if (!panelUp || !(haveContainer || [self hasRecentPanelEvent])) {
        [self hidePanelButton];
        return;
    }
    // ⚠️ 无论这次找没找到官方按钮容器都要排重试：Lynx 是异步渲染的，
    //    面板刚打开时容器还没画出来（之前就是因此要切前后台才出现）
    [self schedulePanelButtonReasserts];
    [self showPanelButtonForViewController:top];
}

- (void)hidePanelButton {
    self.panelButton.hidden = YES;
    // 按**原始几何**还原官方按钮（幂等：只有真的被压窄过才写一次）
    UIView *container = self.panelButtonContainer;
    if (container && container.superview && !CGRectIsEmpty(self.originalContainerFrame)) {
        CGRect original = self.originalContainerFrame;
        CGRect current = container.frame;
        if (fabs(current.size.width - original.size.width) > 0.5) {
            container.frame = CGRectMake(current.origin.x, current.origin.y, original.size.width, original.size.height);
        }
        UIView *label = self.officialLabel;
        if (label && label.superview == container && !CGRectIsEmpty(self.originalLabelFrame) &&
            fabs(label.frame.origin.x - self.originalLabelFrame.origin.x) > 0.5) {
            label.frame = self.originalLabelFrame;
        }
    }
}

- (void)showPanelButtonForViewController:(UIViewController *)controller {
    // ① 必须是真·气泡详情面板：只认 BDXPopup（商店页本身也是 Lynx 页，不能误判）
    NSString *cls = NSStringFromClass([controller class]);
    BOOL panelUp = [cls containsString:@"BDXPopup"];
    BOOL haveContainer = (self.panelButtonContainer && self.panelButtonContainer.superview != nil);
    if (!panelUp || !(haveContainer || [self hasRecentPanelEvent])) {
        [self hidePanelButton];
        return;
    }
    // ② 必须在面板里找到官方主按钮的容器 —— 找不到就不显示（**不做悬浮兜底**，
    //    宁可没有按钮，也不要漂在面板外面）
    //    注意：容器会被我们压窄，压窄后就再也匹配不上"整宽"判据了 —— 所以找到过就记住它。
    UIView *container = self.panelButtonContainer;
    // 记住的容器必须**属于当前这个面板**（上一个面板的视图可能还被短暂持有，
    // 若盲目复用会去压窄上一个面板的按钮 ✗）
    BOOL containerBelongsToPanel = (container && container.superview && [container isDescendantOfView:controller.view]);
    if (!containerBelongsToPanel) {
        self.panelButtonContainer = nil;
        self.officialLabel = nil;
        self.originalContainerFrame = CGRectZero;
        self.originalLabelFrame = CGRectZero;
        container = [self primaryButtonContainerInView:controller.view];
        self.panelButtonContainer = container;
    }
    UIView *host = container.superview;
    if (!container || !host) {
        [self hidePanelButton];
        return;
    }

    // 第一次见到这个容器时，把它的**原始**几何记下来 ——
    // ⚠️ 关键：之后每次都从原始宽度算，绝不能拿"已经被我压窄过的当前宽度"再算一次
    //    （那会一路收敛到钳位值：官方 120 + 本地 96，就是"两颗短条挤在左边"那个样子）
    CGRect containerFrame = container.frame;
    if (CGRectIsEmpty(self.originalContainerFrame)) {
        self.originalContainerFrame = containerFrame;
        for (UIView *sub in container.subviews) {
            if ([NSStringFromClass([sub class]) containsString:@"LynxText"]) {
                self.officialLabel = sub;
                self.originalLabelFrame = sub.frame;
                break;
            }
        }
    }
    CGFloat totalWidth = self.originalContainerFrame.size.width;
    CGFloat height = self.originalContainerFrame.size.height;
    CGFloat gap = 8.0;
    CGFloat ourWidth = MAX(96.0, totalWidth * 0.40);
    CGFloat officialWidth = MAX(120.0, totalWidth - ourWidth - gap);
    CGFloat shift = (totalWidth - officialWidth) / 2.0;

    if (fabs(containerFrame.size.width - officialWidth) > 0.5 || fabs(containerFrame.size.height - height) > 0.5) {
        container.frame = CGRectMake(containerFrame.origin.x, containerFrame.origin.y, officialWidth, height);
    }
    // 官方按钮里那行文字跟着往左挪，保持视觉居中（目标位置与 Lynx 自己居中的结果一致，不会互相打架）
    UIView *label = self.officialLabel;
    if (label && label.superview == container && !CGRectIsEmpty(self.originalLabelFrame)) {
        CGRect target = self.originalLabelFrame;
        target.origin.x -= shift;
        if (fabs(label.frame.origin.x - target.origin.x) > 0.5) {
            label.frame = target;
        }
    }

    if (!self.panelButton) {
        DYYYLocalBubbleButton *button = [[DYYYLocalBubbleButton alloc] initWithFrame:CGRectMake(0, 0, ourWidth, height)];
        [button addTarget:self action:@selector(handlePanelButtonTap) forControlEvents:UIControlEventTouchUpInside];
        self.panelButton = button;
    }
    if (self.panelButton.superview != host) {
        [self.panelButton removeFromSuperview];
        [host addSubview:self.panelButton];
    }
    // 用官方按钮自身的颜色做描边与文字色（这样两颗看起来是一套的）
    self.panelButton.tintColor = container.backgroundColor;
    self.panelButton.frame = CGRectMake(CGRectGetMaxX(container.frame) + gap, containerFrame.origin.y, ourWidth, height);
    self.panelButton.layer.cornerRadius = height / 2.0;
    self.panelButton.hidden = NO;
    [self.panelButton refreshAppearance];
    [host bringSubviewToFront:self.panelButton];
    [self schedulePanelButtonReasserts];
}

/// 在面板视图树里找官方主按钮的容器：整宽（≥85% 屏宽）、高度 38~60、位于下半屏、有不透明底色，
/// 且**内部含 Lynx 文本节点**（官方按钮里就一行 `LynxTextView · 兑换并装扮`）。
/// 命中多个时取**面积最大的那个**（= 最外层的整宽容器），红/粉底的再加权。
/// ⚠️ Lynx 内容是异步渲染的：刚打开面板时可能还找不到，调用方要密集重试。
- (UIView *)primaryButtonContainerInView:(UIView *)root {
    if (!root) {
        return nil;
    }
    CGSize screen = [UIScreen mainScreen].bounds.size;
    UIWindow *window = [self hostWindow];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    UIView *best = nil;
    CGFloat bestScore = 0;
    int visited = 0;
    while (queue.count > 0 && visited < 6000) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visited++;
        [queue addObjectsFromArray:view.subviews];

        CGRect frame = view.frame;
        // 只要**整宽**的那一层（384pt），别挑到内层的小容器（否则两颗会挤在左边留一片空白）
        if (frame.size.width < screen.width * 0.85 || frame.size.height < 38.0 || frame.size.height > 60.0) {
            continue;
        }
        CGRect inWindow = [view.superview convertRect:frame toView:window];
        if (CGRectGetMidY(inWindow) < screen.height * 0.5) {
            continue;
        }
        UIColor *color = view.backgroundColor;
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if (!color || ![color getRed:&r green:&g blue:&b alpha:&a] || a < 0.5) {
            continue;
        }
        if (![self containsLynxTextDescendant:view]) {
            continue;   // 官方按钮容器里一定有那行文字
        }
        // 取面积最大的那个（最外层），红/粉底再加权
        CGFloat score = frame.size.width * frame.size.height;
        if (r > 0.7 && g < 0.55 && b < 0.65) {
            score *= 1.5;
        }
        if (score > bestScore) {
            bestScore = score;
            best = view;
        }
    }
    return best;
}

- (BOOL)containsLynxTextDescendant:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([NSStringFromClass([sub class]) containsString:@"LynxText"]) {
            return YES;
        }
        if ([self containsLynxTextDescendant:sub]) {
            return YES;
        }
    }
    return NO;
}

/// Lynx 是异步渲染的：先说一句"尽快、密集地试"——面板打开后几十毫秒内就把按钮摆好，
/// 让用户几乎看不到"官方按钮先单独出现、再分成两颗"的过程；之后再慢速兜底（Lynx 重画时补回来）。
- (void)schedulePanelButtonReasserts {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - self.lastReassertScheduleTime < 2.0) {
        return;   // 别把轮询叠起来
    }
    self.lastReassertScheduleTime = now;
    // 密集轮询：立刻试一次，然后 0.06 秒一次，持续约 1.5 秒
    for (int i = 0; i <= 25; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self updatePanelButtonForTopViewController];
        });
    }
    // 慢速兜底：2 秒后再确认几拍（Lynx 重画 / 数据刷新时能补回来）
    for (NSNumber *delay in @[ @2.0, @2.6, @3.4 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([delay doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self updatePanelButtonForTopViewController];
        });
    }
}

#pragma mark - 面板按钮：点击

- (void)handlePanelButtonTap {
    DYYYChatBubbleDress *dress = self;
    if (!dress.enabled) {
        // 设置里总开关被关掉时，按钮即使还挂在面板上也不该起作用
        [DYYYToast showSuccessToastWithMessage:@"「本地气泡装扮」已在设置里关闭"];
        [self.panelButton refreshAppearance];
        return;
    }
    BOOL isCurrentPanelBubble = (dress.active && dress.panelBubbleID.length > 0 &&
                                 [dress.localBubbleID isEqualToString:dress.panelBubbleID]);
    if (isCurrentPanelBubble) {
        // 当前装扮的就是这个气泡 → 恢复官方
        [self clearLocalBubble];
        [self.panelButton refreshAppearance];
        [DYYYToast showSuccessToastWithMessage:@"已恢复装扮（退出聊天再进生效）"];
        return;
    }
    NSString *bubbleID = self.panelBubbleID;
    if (bubbleID.length == 0) {
        [DYYYToast showSuccessToastWithMessage:@"还没读到这个气泡，关掉面板重进一次"];
        return;
    }
    [self applyLocalBubbleID:bubbleID name:self.panelBubbleName];
    [self.panelButton refreshAppearance];
    [DYYYToast showSuccessToastWithMessage:@"本地装扮成功"];
}

@end
