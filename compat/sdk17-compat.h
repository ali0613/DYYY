//
//  compat/sdk17-compat.h
//
//  工具链垫片（不是功能代码，不要往里加业务逻辑）。
//
//  成因：本机 SDK 是 iPhoneOS16.5.sdk，而 DYYY 源码里用了一处 iOS 17 API：
//      DYYY.xm  DYYYApplySDRDynamicRangeToImageView()
//          imageView.preferredImageDynamicRange = UIImageDynamicRangeStandard;
//  在 16.5 SDK 下这两个符号都不存在：
//    - 属性：编译期报 "property not found"       → 本文件补一个 UIImageView 声明；
//    - 常量：链接期报 "_UIImageDynamicRangeStandard not found" → 本文件用 dlsym 取真值。
//  这样做的目的是保持上游 DYYY.xm 逐字节不变，本分支的源码差异为零。
//
//  安全性：唯一使用点包在 `if (@available(iOS 17.0, *))` 内，而 @available 的判定由
//  compat/osversion-compat.m 提供真实版本比较 —— iOS 16 设备永远不会执行到这里，
//  dlsym 也不会被调用（真被调到也只是返回 nil，不会崩）。
//
//  一旦本地 SDK 升到 iOS 17+，本文件整体失效（#if 直接跳过），可以直接删掉。
//

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 170000

#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef NSString *UIImageDynamicRange NS_TYPED_EXTENSIBLE_ENUM;

@interface UIImageView (SDK17Compat)
@property (nonatomic, copy) UIImageDynamicRange preferredImageDynamicRange;
@end

// 从进程里已加载的 UIKit 取 Apple 真实的常量对象，避免自己硬编码字符串值
// （同时也避开了 16.5 SDK 里没有这个导出符号、链接不过的问题）。
static inline UIImageDynamicRange DYYYSDK17CompatDynamicRangeStandard(void) {
    static UIImageDynamicRange value;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "UIImageDynamicRangeStandard");
        value = symbol ? *(UIImageDynamicRange const *)symbol : nil;
    });
    return value;
}

#define UIImageDynamicRangeStandard DYYYSDK17CompatDynamicRangeStandard()

#endif
