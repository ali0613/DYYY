//
//  DYYYLiveChannel.m
//  DYYY
//
//  调试专用实时通道：见头文件。实现要点：
//  - 只用 BSD socket + GCD dispatch source，不引入任何依赖；
//  - 所有网络 IO 在私有串行队列上，主线程零阻塞（读写都带超时）；
//  - 诊断开关关闭时完全不启动，正式包删掉本文件即可。
//

#import "DYYYLiveChannel.h"
#import "DYYYDetailDiagnostics.h"
#import "AwemeHeaders.h"

#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

static const NSInteger kDYYYLivePort = 8899;
static NSString *const kDYYYLiveSwitchKey = @"DYYYDetailDiag";
static NSString *const kDYYYLiveParamPrefix = @"DYYYLiveParam.";

static int gDYYYListenFD = -1;
static NSInteger gDYYYListenPort = 0;
static dispatch_source_t gDYYYListenSource = NULL; // 必须持有：dispatch source 不会被自动保活
static dispatch_queue_t gDYYYLiveQueue = NULL;
static BOOL gDYYYLiveStarted = NO;
static NSInteger gDYYYCellMode = -1;
static NSInteger gDYYYOverlayMode = -1;
static NSInteger gDYYYPlayerMode = -1;
static NSInteger gDYYYTablePadMode = -1;
static CGFloat gDYYYExtra = CGFLOAT_MAX;

@implementation DYYYLiveChannel

#pragma mark - 参数（带内存缓存，避免布局回调里频繁读 NSUserDefaults）

+ (NSInteger)cachedIntegerForName:(NSString *)name defaultValue:(NSInteger)defaultValue current:(NSInteger *)slot {
    if (*slot < 0) {
        NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:[kDYYYLiveParamPrefix stringByAppendingString:name]];
        *slot = stored ? stored.integerValue : defaultValue;
    }
    return *slot;
}

+ (void)storeInteger:(NSInteger)value forName:(NSString *)name slot:(NSInteger *)slot {
    *slot = value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:[kDYYYLiveParamPrefix stringByAppendingString:name]];
}

+ (NSInteger)detailTablePadMode {
    return [self cachedIntegerForName:@"tablepad" defaultValue:1 current:&gDYYYTablePadMode];
}

+ (NSInteger)detailCellMode {
    return [self cachedIntegerForName:@"cell" defaultValue:1 current:&gDYYYCellMode];
}

+ (NSInteger)detailOverlayMode {
    return [self cachedIntegerForName:@"overlay" defaultValue:1 current:&gDYYYOverlayMode];
}

+ (NSInteger)detailPlayerMode {
    return [self cachedIntegerForName:@"player" defaultValue:1 current:&gDYYYPlayerMode];
}

+ (CGFloat)detailExtra {
    if (gDYYYExtra == CGFLOAT_MAX) {
        NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:[kDYYYLiveParamPrefix stringByAppendingString:@"extra"]];
        gDYYYExtra = stored ? (CGFloat)stored.doubleValue : 0.0;
    }
    return gDYYYExtra;
}

+ (void)applyParameter:(NSString *)key value:(NSString *)value {
    if ([key isEqualToString:@"tablepad"]) {
        [self storeInteger:value.integerValue forName:@"tablepad" slot:&gDYYYTablePadMode];
    } else if ([key isEqualToString:@"cell"]) {
        [self storeInteger:value.integerValue forName:@"cell" slot:&gDYYYCellMode];
    } else if ([key isEqualToString:@"overlay"]) {
        [self storeInteger:value.integerValue forName:@"overlay" slot:&gDYYYOverlayMode];
    } else if ([key isEqualToString:@"player"]) {
        [self storeInteger:value.integerValue forName:@"player" slot:&gDYYYPlayerMode];
    } else if ([key isEqualToString:@"extra"]) {
        gDYYYExtra = (CGFloat)value.doubleValue;
        [[NSUserDefaults standardUserDefaults] setDouble:gDYYYExtra forKey:[kDYYYLiveParamPrefix stringByAppendingString:@"extra"]];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)stateDescription {
    return [NSString stringWithFormat:@"cell=%ld overlay=%ld player=%ld tablepad=%ld extra=%.1f",
                                      (long)[self detailCellMode], (long)[self detailOverlayMode],
                                      (long)[self detailPlayerMode], (long)[self detailTablePadMode],
                                      [self detailExtra]];
}

#pragma mark - 服务生命周期

+ (void)startIfNeeded {
    if (gDYYYLiveStarted) {
        return;
    }
    gDYYYLiveStarted = YES;

    if (!DYYYGetBool(kDYYYLiveSwitchKey)) {
        return;
    }

    gDYYYLiveQueue = dispatch_queue_create("com.dyyy.livechannel", DISPATCH_QUEUE_SERIAL);

    // 8899 起，往后找 10 个端口，避免与应用自身服务冲突
    for (NSInteger port = kDYYYLivePort; port < kDYYYLivePort + 10; port++) {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            return;
        }
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons((uint16_t)port);
        addr.sin_addr.s_addr = htonl(INADDR_ANY);

        if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(fd, 8) != 0) {
            close(fd);
            continue;
        }

        gDYYYListenFD = fd;
        gDYYYListenPort = port;
        gDYYYListenSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, gDYYYLiveQueue);
        dispatch_source_set_event_handler(gDYYYListenSource, ^{
          [self acceptPendingConnection];
        });
        dispatch_resume(gDYYYListenSource);
        NSLog(@"[DYYY] live channel 已监听 :%ld", (long)port);
        return;
    }
    NSLog(@"[DYYY] live channel 启动失败：%ld-%ld 全部被占用", (long)kDYYYLivePort, (long)(kDYYYLivePort + 9));
}

#pragma mark - 连接处理

+ (void)acceptPendingConnection {
    int client = accept(gDYYYListenFD, NULL, NULL);
    if (client < 0) {
        return;
    }

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    char buffer[2048];
    memset(buffer, 0, sizeof(buffer));
    ssize_t got = recv(client, buffer, sizeof(buffer) - 1, 0);
    NSString *reply = @"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";

    if (got > 0) {
        NSString *request = [NSString stringWithUTF8String:buffer];
        NSString *firstLine = [[request componentsSeparatedByString:@"\r\n"] firstObject];
        NSArray<NSString *> *parts = [firstLine componentsSeparatedByString:@" "];
        NSString *path = parts.count > 1 ? parts[1] : @"/";

        NSString *body = [self responseBodyForPath:path];
        NSLog(@"[DYYY] live %@ -> %lu 字节", path, (unsigned long)body.length);
        reply = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n"
                                           @"Content-Length: %lu\r\nConnection: close\r\n\r\n%@",
                                           (unsigned long)[body lengthOfBytesUsingEncoding:NSUTF8StringEncoding], body];
    }

    NSData *data = [reply dataUsingEncoding:NSUTF8StringEncoding];
    send(client, data.bytes, data.length, 0);
    close(client);
}

+ (NSString *)responseBodyForPath:(NSString *)path {
    if ([path hasPrefix:@"/ping"]) {
        return @"ok";
    }
    if ([path hasPrefix:@"/clear"]) {
        [DYYYDetailDiagnostics reset];
        return @"cleared";
    }
    if ([path hasPrefix:@"/set?"]) {
        NSString *query = [path substringFromIndex:5];
        for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
            NSArray<NSString *> *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count == 2) {
                [self applyParameter:kv[0] value:kv[1]];
            }
        }
        return [NSString stringWithFormat:@"ok %@", [self stateDescription]];
    }
    if ([path hasPrefix:@"/state"]) {
        NSString *text = [DYYYDetailDiagnostics collectedText] ?: @"";
        if (text.length > 9000) {
            text = [text substringFromIndex:text.length - 9000];
        }
        return [NSString stringWithFormat:@"params: %@\n--- diag ---\n%@", [self stateDescription], text];
    }
    return @"DYYY live channel\n/state\n/set?cell=1&overlay=1&player=1&tablepad=1&extra=0\n/clear\n/ping\n";
}

@end
