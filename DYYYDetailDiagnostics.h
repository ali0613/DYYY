//
//  DYYYDetailDiagnostics.h
//  DYYY
//
//  临时诊断工具（默认关闭，开关 key：DYYYDetailDiag）
//  用途：把「首页全屏」在作品详情页上的高度补偿现场数据（frame、高度、控制器层级、
//        tabBar 高度）落到文件并复制到剪贴板，便于真机取证。
//  取证结束后整个类可以删除：删掉本文件与 DYYYDetailDiagnostics.m，
//  再移除 DYYY.xm 里的 captureWithTag 调用与设置页里的开关项即可。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYDetailDiagnostics : NSObject

/** 诊断开关是否打开 */
+ (BOOL)isEnabled;

/**
 * 采集一次现场数据。
 * @param tag 采集点标识（同名 tag 有节流：0.8 秒内只记一次）
 * @param context 需要记录的键值对（值用 NSString/NSNumber，nil 用 @"(nil)"）
 * @param view 用于推导视图与控制器层级，可为 nil
 */
+ (void)captureWithTag:(NSString *)tag
               context:(nullable NSDictionary<NSString *, id> *)context
                  view:(nullable UIView *)view;

/** 当前已收集的全部文本 */
+ (NSString *)collectedText;

/**
 * 判断视图是否处在「作品详情页」里（响应者链上出现 AWEAwemeDetail / AWEMixVideoPanelDetail）。
 * 详情页本身没有首页底栏，这一点是后续修正高度补偿的判定依据。
 */
+ (BOOL)isInDetailPageFromView:(nullable UIView *)view;

/**
 * 采集一次视图结构快照（用于看清视频框 / cell / 容器各自的实际高度）。
 * @param root 结构根视图（例如详情页表格）
 * @param tag 采集点标识
 * @param note 附加说明
 */
+ (void)captureStructureFromView:(nullable UIView *)root tag:(NSString *)tag note:(nullable NSString *)note;

/** 清空缓冲并删除落盘文件 */
+ (void)reset;

@end

NS_ASSUME_NONNULL_END
