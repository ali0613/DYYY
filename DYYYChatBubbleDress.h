//
//  DYYYChatBubbleDress.h
//  DYYY
//
//  「本地气泡装扮」：把气泡商店里的皮肤套到**自己发出去**的聊天气泡上（仅本机渲染，不改服务端状态）。
//
//  实现要点（真机实证，见 FORK.md 第二十二节）：
//    · 抖音按「每条消息自带的 bubbleID」渲染气泡，气泡资源的缓存键是 `<bubbleID>_self`（我发的）/
//      `<bubbleID>_peer`（对方）；文字颜色在 `getCacheOtherSettingWithBubbleID:` 的 text_color 字段，
//      且用**裸 id**（无后缀）读取。
//    · 所以「换皮」= 在读取缓存时，把「我当前气泡 id」的键换成本地 id 的键；
//      未拥有的气泡资源可用 `AWEIMUserBubbleComponent - tryRequestBubbleImageWithBubbleID:` 按 id 拉取。
//    · 面板（气泡详情半屏）是 Lynx 页面，条目 id/名字从桥接事件
//      `BDXBridgeReportAppLogMethod` 的 params 里 bubble_id / bubble_name 精确取得。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYChatBubbleDress : NSObject

+ (instancetype)sharedInstance;

/// 设置页总开关（`DYYYEnableBubbleDress`，缺省视为开）
@property (nonatomic, assign, readonly) BOOL enabled;
/// 已记住的本地气泡（`DYYYLocalBubbleID` / `DYYYLocalBubbleName` 持久化）
@property (nonatomic, copy, readonly, nullable) NSString *localBubbleID;
@property (nonatomic, copy, readonly, nullable) NSString *localBubbleName;
/// 生效中 = 总开关开着 && 记住了本地气泡
@property (nonatomic, assign, readonly) BOOL active;

/// 一次气泡资源读取的键（用于推断"我当前的官方气泡 id"并持久化 —— 它一次启动可能只被抖音读一次，
/// 重启后直接进聊天时拿不到，靠键推断最稳）
- (void)noteBubbleKeyObserved:(id)key;

/// 我当前的官方气泡 id（由键推断或 AWEIMUserBubbleUtility 钩子喂进来）
@property (nonatomic, copy, nullable) NSString *currentUserBubbleID;

#pragma mark - 抓取（桥接事件）

/// 桥接上报参数进来（内部按 params[@"bubble_id" / @"bubble_name"] 精确解析）
- (void)handleBridgeParamModel:(id)model;
/// 最近一次「气泡兑换面板」事件是否还新鲜（用于决定按钮显不显示）
- (BOOL)hasRecentPanelEvent;
/// 面板里当前这个气泡
@property (nonatomic, copy, readonly, nullable) NSString *panelBubbleID;
@property (nonatomic, copy, readonly, nullable) NSString *panelBubbleName;

#pragma mark - 应用 / 清除

- (void)applyLocalBubbleID:(NSString *)bubbleID name:(nullable NSString *)name;
- (void)clearLocalBubble;

#pragma mark - 读取键改写

/// 返回改写候选键（空数组 = 不改写）。
/// 只命中「我当前气泡」的裸 id 与 `<id>_self`；`_peer`（对方气泡）与其它气泡一律不动。
- (NSArray<NSString *> *)rewriteCandidatesForKey:(id)key;

#pragma mark - 面板按钮

/// 供 UIViewController 钩子调用：按当前界面决定按钮显隐与位置
- (void)updatePanelButtonForTopViewController;

#pragma mark - 资源预取

/// 记录消息组件实例（进聊天时自动补拉一次本地气泡资源，防缓存被清）
- (void)noteUserBubbleComponent:(id)component;

@end

NS_ASSUME_NONNULL_END
