//
//  DYYYLiveChannel.h
//  DYYY
//
//  调试专用（仅诊断包内存在，默认随「详情页诊断」开关一起关着）：
//  在设备本地开一个极简 HTTP 服务（端口 8899），用于电脑端实时读写：
//
//      GET /state          读取当前诊断文本（实时视图结构/高度数据）
//      GET /set?cell=1&overlay=1&player=1&tablepad=1&extra=0
//                          运行时调整详情页各处补偿（立即生效，无需重装）
//      GET /clear          清空诊断缓冲
//      GET /ping           -> ok
//
//  参数默认值 = 当前正式行为（cell=1 overlay=1 player=1 tablepad=1 extra=0），
//  「详情页诊断」开关关闭时这个服务不会启动。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYLiveChannel : NSObject

/** 开关打开时启动本地服务（可重复调用，只启动一次） */
+ (void)startIfNeeded;

/** 详情页表格补整：0=关闭，1=补成整屏（默认） */
+ (NSInteger)detailTablePadMode;

/** 详情页 cell 补齐：0=关闭，1=按屏幕高度补齐（默认），2=按表格高度补齐 */
+ (NSInteger)detailCellMode;

/** 详情页交互层：0=按旧逻辑减底栏，1=按满高（默认） */
+ (NSInteger)detailOverlayMode;

/** 详情页播放器：0=关闭，1=按所在容器满高补齐（默认） */
+ (NSInteger)detailPlayerMode;

/** 额外补偿点数（正负皆可，实验用，默认 0） */
+ (CGFloat)detailExtra;

@end

NS_ASSUME_NONNULL_END
