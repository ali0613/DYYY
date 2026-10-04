//
//  compat/osversion-compat.m
//
//  工具链垫片（不是功能代码，不要往里加业务逻辑）。
//
//  成因：本机 theos 用的 Linux 交叉工具链是 llvm clang 11.1.0，不带 compiler-rt。
//  源码里每一处 `@available(...)` / `__builtin_available(...)` 都会被 clang 编译成对
//  `__isOSVersionAtLeast(major, minor, patch)` 的调用，链接期就会报：
//      Undefined symbols for architecture arm64: "___isOSVersionAtLeast"
//
//  语义必须与 compiler-rt 的实现一致：当前系统版本 >= 请求版本返回 1，否则返回 0。
//  严禁简单 return 1 —— 那会让 iOS 17/18 专属分支在 iOS 16 上执行（例如给
//  UIImageView 设置 iOS 17 才有的 preferredImageDynamicRange）。
//
//  必须是 weak 定义：Apple 工具链（Xcode）链接时会带进 libclang_rt.ios.a 里的
//  os_version_check.c.o，它已经定义了同一个符号；强定义会直接撞成
//      duplicate symbol '___isOSVersionAtLeast'
//  weak 定义在两边都正确：macOS/Apple 工具链上强定义胜出（我们这份被忽略），
//  本机 Linux 交叉工具链没有别的定义时由我们这份兜底。
//

#import <Foundation/Foundation.h>

__attribute__((weak)) int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t patch) {
    static NSOperatingSystemVersion current;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        current = [NSProcessInfo processInfo].operatingSystemVersion;
    });

    if (current.majorVersion != major) {
        return current.majorVersion > major;
    }
    if (current.minorVersion != minor) {
        return current.minorVersion > minor;
    }
    return current.patchVersion >= patch;
}
