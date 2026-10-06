//
//  DYYYChatBubbleDress.xm
//  DYYY
//
//  「本地气泡装扮」的 Hook 层：只做四件事
//    ① 记住"我当前的官方气泡 id"（改写判定要靠它）
//    ② 气泡资源读取时，把我当前气泡的键改写成本地气泡的键
//    ③ 从桥接上报参数里精确抓取面板里那个气泡的 id / 名字
//    ④ 面板打开时挂上「本地装扮」按钮（只在这个页面显示）
//
//  安全性：任何一步读不到都**原样返回**（安全降级到官方气泡），绝不出现空气泡。
//

#import "DYYYChatBubbleDress.h"
#import "AwemeHeaders.h"
#import <UIKit/UIKit.h>

// ① 我当前的官方气泡 id
%hook AWEIMUserBubbleUtility

- (id)currentUserBubbleID {
    id value = %orig;
    if ([value isKindOfClass:[NSString class]]) {
        [DYYYChatBubbleDress sharedInstance].currentUserBubbleID = value;
    }
    return value;
}

%end

// ② 气泡资源读取改写（图片 / flex 布局 / 其它设置 三族，内存 / 磁盘 / 缓存三种来源）
%hook AWEIMUserBubbleCacheManager

- (id)localImageForKey:(id)key {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:key];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:key]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)memoryImageForKey:(id)key {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:key];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:key]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)diskImageForKey:(id)key {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:key];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:key]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)getCacheFlexSettingWithBubbleID:(id)bubbleID {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:bubbleID];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:bubbleID]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)getDiskFlexSettingWithBubbleID:(id)bubbleID {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:bubbleID];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:bubbleID]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)getMemoryFlexSettingWithBubbleID:(id)bubbleID {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:bubbleID];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:bubbleID]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

// 文字颜色走这一族（注意：抖音是用**裸 id**读的，不带 _self / _peer 后缀）
- (id)getCacheOtherSettingWithBubbleID:(id)bubbleID {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:bubbleID];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:bubbleID]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)getDiskOtherSettingWithBubbleID:(id)bubbleID {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:bubbleID];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:bubbleID]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

- (id)getMemoryOtherBubbleSettingWithBubbleID:(id)bubbleID {
    [[DYYYChatBubbleDress sharedInstance] noteBubbleKeyObserved:bubbleID];
    for (NSString *candidate in [[DYYYChatBubbleDress sharedInstance] rewriteCandidatesForKey:bubbleID]) {
        id value = %orig(candidate);
        if (value) {
            return value;
        }
    }
    return %orig;
}

%end

// ③ 面板里那个气泡：Lynx 页会用自己的上报事件把 bubble_id / bubble_name 递出来
%hook BDXBridgeReportAppLogMethod

- (void)callWithParamModel:(id)model completionHandler:(id)handler {
    [[DYYYChatBubbleDress sharedInstance] handleBridgeParamModel:model];
    %orig;
}

%end

// ④ 进聊天时记录消息组件实例（用于把本地气泡的资源补拉一次，防缓存被清）
%hook AWEIMUserBubbleComponent

- (BOOL)p_isTargetSelfBubbleWithMessage:(id)message {
    [[DYYYChatBubbleDress sharedInstance] noteUserBubbleComponent:self];
    return %orig;
}

%end

// ④ 面板按钮的显隐（只在气泡详情面板打开时出现）
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[DYYYChatBubbleDress sharedInstance] updatePanelButtonForTopViewController];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[DYYYChatBubbleDress sharedInstance] updatePanelButtonForTopViewController];
}

%end
