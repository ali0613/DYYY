//
//  DYYYDetailDiagnostics.m
//  DYYY
//
//  临时诊断工具：见头文件说明。默认关闭，只有打开开关才会记录，关闭时零开销
//  （每次调用只做一次 NSUserDefaults 读取）。
//

#import "DYYYDetailDiagnostics.h"
#import "AwemeHeaders.h"
#import "DYYYUtils.h"

static NSString *const kDYYYDetailDiagnosticsSwitchKey = @"DYYYDetailDiag";

static const NSTimeInterval kDYYYDiagSameTagInterval = 0.8;    // 同一采集点的最小间隔
static const NSTimeInterval kDYYYDiagPasteboardInterval = 3.0; // 剪贴板写入最小间隔（避免频繁覆盖）
static const NSTimeInterval kDYYYDiagToastInterval = 30.0;     // 提示最小间隔
static const NSUInteger kDYYYDiagMaxLines = 400;               // 缓冲上限（超出后裁掉前半）
static const NSUInteger kDYYYDiagMaxTextLength = 12000;        // 剪贴板文本上限

static NSMutableString *gDYYYDiagBuffer = nil;
static NSMutableDictionary<NSString *, NSDate *> *gDYYYDiagLastCapture = nil;
static NSDate *gDYYYDiagLastPasteboard = nil;
static NSDate *gDYYYDiagLastToast = nil;
static dispatch_queue_t gDYYYDiagIOQueue = NULL;
static NSDateFormatter *gDYYYDiagFormatter = nil;
static NSString *gDYYYDiagFilePath = nil;

@implementation DYYYDetailDiagnostics

#pragma mark - 开关

+ (BOOL)isEnabled {
    return DYYYGetBool(kDYYYDetailDiagnosticsSwitchKey);
}

#pragma mark - 采集

+ (void)captureWithTag:(NSString *)tag
               context:(NSDictionary<NSString *, id> *)context
                  view:(UIView *)view {
    if (![self isEnabled] || tag.length == 0) {
        return;
    }

    // 布局回调可能在非主线程，统一回主线程（读取视图层级必须主线程）
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self captureWithTag:tag context:context view:view];
        });
        return;
    }

    [self prepareIfNeeded];

    NSDate *now = [NSDate date];
    NSDate *lastCapture = gDYYYDiagLastCapture[tag];
    if (lastCapture && [now timeIntervalSinceDate:lastCapture] < kDYYYDiagSameTagInterval) {
        return;
    }
    gDYYYDiagLastCapture[tag] = now;

    NSMutableString *entry = [NSMutableString string];
    if (gDYYYDiagBuffer.length == 0) {
        [entry appendString:[self sessionHeader]];
    }

    [entry appendFormat:@"[%@] %@\n", [gDYYYDiagFormatter stringFromDate:now], tag];
    for (NSString *key in [[context allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [entry appendFormat:@"    %@ = %@\n", key, context[key] ?: @"(nil)"];
    }
    if (view) {
        [entry appendFormat:@"    view = %@ frame=%@", NSStringFromClass([view class]), NSStringFromCGRect(view.frame)];
        [entry appendFormat:@" super = %@\n", view.superview ? NSStringFromCGRect(view.superview.frame) : @"(nil)"];
        [entry appendFormat:@"    vc链 = %@\n", [self viewControllerChainDescriptionFromView:view]];
    }

    [gDYYYDiagBuffer appendString:entry];
    [self trimBufferIfNeeded];
    [self persistWithToastAllowed:YES];
}

#pragma mark - 落盘 / 剪贴板

+ (void)persistWithToastAllowed:(BOOL)toastAllowed {
    NSString *text = [gDYYYDiagBuffer copy];
    dispatch_async(gDYYYDiagIOQueue, ^{
      NSFileManager *fm = [NSFileManager defaultManager];
      NSString *dir = [gDYYYDiagFilePath stringByDeletingLastPathComponent];
      if (![fm fileExistsAtPath:dir]) {
          [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
      }
      [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:gDYYYDiagFilePath atomically:YES];
    });

    NSDate *now = [NSDate date];
    if (!gDYYYDiagLastPasteboard || [now timeIntervalSinceDate:gDYYYDiagLastPasteboard] >= kDYYYDiagPasteboardInterval) {
        gDYYYDiagLastPasteboard = now;
        NSString *pasteboardText = text;
        if (pasteboardText.length > kDYYYDiagMaxTextLength) {
            pasteboardText = [pasteboardText substringFromIndex:pasteboardText.length - kDYYYDiagMaxTextLength];
        }
        [UIPasteboard generalPasteboard].string = pasteboardText;

        if (toastAllowed && (!gDYYYDiagLastToast || [now timeIntervalSinceDate:gDYYYDiagLastToast] >= kDYYYDiagToastInterval)) {
            gDYYYDiagLastToast = now;
            [DYYYUtils showToast:@"详情页诊断：已复制到剪贴板"];
        }
    }
}

#pragma mark - 缓冲维护

+ (void)trimBufferIfNeeded {
    NSUInteger lineCount = 0;
    for (NSUInteger i = 0; i < gDYYYDiagBuffer.length; i++) {
        if ([gDYYYDiagBuffer characterAtIndex:i] == '\n') {
            lineCount++;
        }
    }
    if (lineCount <= kDYYYDiagMaxLines) {
        return;
    }

    // 超限就把前半段丢掉，保留最近的记录
    NSRange cut = [gDYYYDiagBuffer rangeOfString:@"\n" options:0
                                           range:NSMakeRange(gDYYYDiagBuffer.length / 2, gDYYYDiagBuffer.length - gDYYYDiagBuffer.length / 2)];
    if (cut.location != NSNotFound) {
        [gDYYYDiagBuffer deleteCharactersInRange:NSMakeRange(0, NSMaxRange(cut))];
    }
}

#pragma mark - 描述信息

+ (NSString *)sessionHeader {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";
    UIScreen *screen = [UIScreen mainScreen];
    return [NSString stringWithFormat:@"==== DYYY 详情页诊断 ====\n抖音版本: %@ (%@)  屏幕: %.0fx%.0f\n首页全屏: %@  首页净化: %@\n",
                                      version, build, screen.bounds.size.width, screen.bounds.size.height,
                                      DYYYGetBool(@"DYYYEnableFullScreen") ? @"开" : @"关",
                                      DYYYGetBool(@"DYYYEnablePure") ? @"开" : @"关"];
}

+ (NSString *)viewControllerChainDescriptionFromView:(UIView *)view {
    UIResponder *responder = view;
    UIViewController *controller = nil;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            controller = (UIViewController *)responder;
            break;
        }
        responder = responder.nextResponder;
    }

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSInteger depth = 0;
    while (controller && depth < 8) {
        [names addObject:NSStringFromClass([controller class])];
        controller = controller.parentViewController;
        depth++;
    }
    return names.count > 0 ? [names componentsJoinedByString:@" < "] : @"(未找到控制器)";
}

#pragma mark - 对外查询 / 重置

+ (NSString *)collectedText {
    return [gDYYYDiagBuffer copy] ?: @"";
}

+ (void)reset {
    gDYYYDiagBuffer = [NSMutableString string];
    [gDYYYDiagLastCapture removeAllObjects];
    gDYYYDiagLastPasteboard = nil;
    gDYYYDiagLastToast = nil;
    if (gDYYYDiagFilePath) {
        [[NSFileManager defaultManager] removeItemAtPath:gDYYYDiagFilePath error:NULL];
    }
}

#pragma mark - 初始化

+ (void)prepareIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      gDYYYDiagBuffer = [NSMutableString string];
      gDYYYDiagLastCapture = [NSMutableDictionary dictionary];
      gDYYYDiagIOQueue = dispatch_queue_create("com.dyyy.detaildiagnostics.io", DISPATCH_QUEUE_SERIAL);
      gDYYYDiagFormatter = [[NSDateFormatter alloc] init];
      gDYYYDiagFormatter.dateFormat = @"HH:mm:ss.SSS";

      NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
      if (documents.length == 0) {
          documents = NSTemporaryDirectory();
      }
      gDYYYDiagFilePath = [[documents stringByAppendingPathComponent:@"DYYY"] stringByAppendingPathComponent:@"详情页诊断.txt"];
    });
}

@end
