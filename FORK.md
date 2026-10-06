# FORK.md —— 本仓库是什么、怎么维护

## 一、定位与仓库关系

`D:\xiazai\dsh\dyyy` = **DYYY 的个人维护分支**，用于长期跟进并适配新版本抖音。

| remote | 地址 | 用途 |
|---|---|---|
| `origin` | 你自己的仓库（**待设置**：`git remote add origin <你的地址>`） | 日常 push 目标 |
| `upstream` | https://github.com/Wtrwx/DYYY.git | **2.2-9 线，日常同步源**（本仓库的克隆来源） |
| `huami` | https://github.com/huami1314/DYYY.git | 原作者仓库（2.2-8 线），备用参考 |

- 基线：`6bdc7c3` / tag `DYYY_2.2-9#1687`（2026-07-06），上游全历史 2268 个提交都在本地
- 上游分支情况：`main`（最新，2.2-9）> `dev`（2026-01-29）> `ModernUI`（2025-06-25）→ **基线取 `main`**
- 目标环境：抖音 `com.ss.iphone.ugc.Aweme` **39.6.0** / iOS **16.1.1** / **roothide** 越狱
- 上游自述只在抖音 36.5.0 上测过 → 39.6.0 上部分 hook 的类名/方法可能已改名，这是后续维护的主要工作

## 二、与上游的差异（全在构建层，源码零差异）

| 文件 | 差异 | 原因 |
|---|---|---|
| `Makefile` | 替换 | 追加 roothide 架构对齐；`DYYY_FILES` 追加垫片；`DYYY_CFLAGS` 追加 `-include compat/sdk17-compat.h` |
| `control` | 替换 | 基础版本加 fork 修订号 `2.2-9fork2`（> 上游 `2.2-9`，不会被上游包降级覆盖）；`Conflicts/Replaces: com.lcs.dyui` 清掉更早的自研插件包 |
| `compat/osversion-compat.m` | 新增 | 本机 clang 11 无 compiler-rt，`@available` 缺 `___isOSVersionAtLeast` 符号 |
| `compat/sdk17-compat.h` | 新增 | iPhoneOS16.5.sdk 缺 iOS 17 的 `preferredImageDynamicRange` / `UIImageDynamicRangeStandard` |
| `.gitattributes` | 新增 | 强制 LF 行尾，避免 WSL 脚本被 Windows 侧转成 CRLF |
| `FORK.md`、`scripts/` | 新增 | 本文档与构建/校验/环境脚本 |
| 其余 53 个上游文件 | **无差异** | 上游原样（`git diff upstream/main --stat` 可复核） |

## 三、构建

```powershell
# WSL 内构建（roothide 为默认）
wsl -d Ubuntu22 -- bash /mnt/d/xiazai/dsh/dyyy/scripts/build.sh roothide

# 产物校验（包元信息 / 架构 / 垫片符号 / DYYY 类 / 历史自研产物残留 / SHA256）
wsl -d Ubuntu22 -- bash /mnt/d/xiazai/dsh/dyyy/scripts/verify.sh
```

`build.sh` 会 `rsync` 到 `~/dyyy-build`（WSL 原生盘；直接在 `/mnt/d` 上编译会因 drvfs 的符号链接与权限语义失败，且慢十倍）→ `make clean package` → 打印包信息/结构/哈希 → 回传 `packages/`。

环境从零搭建：以 root 跑 `scripts/setup-wsl-theos.sh`。要点：必须用 **roothide/theos**（官方 theos 的 `vendor/mod/` 里没有 roothide，`SCHEME=roothide` 会静默退化成普通包）；工具链是 L1ghtmann 的 llvm（clang 11.1.0，不带 compiler-rt，所以有 `compat/`）。

### 构建层三个坑（改 Makefile 前先读）

1. **包架构由 `control` 决定，不是 `SCHEME`**：`theos/makefiles/package/deb.mk:26` 会从项目 `control` 回读 `Architecture`，覆盖 scheme 模块的值 → roothide 包被标成 `iphoneos-arm`、Sileo 拒绝安装。Makefile 里的 `_DYYY_CONTROL_SYNC` 在解析期用 sed 对齐（`deb.mk:52` 打包时还会删掉 control 里的 Version/Architecture 行重写，最终值由内部变量决定）。
2. **clang 11 没有 compiler-rt**：任何 `@available` 都会引用 `___isOSVersionAtLeast`，链接报 Undefined symbols。垫片必须做**真实版本比较**，不能 `return 1`——否则 iOS 17 专属分支会在 iOS 16 上执行。
3. **16.5 SDK 缺 iOS 17 声明**：`compat/sdk17-compat.h` 用 `-include` 强制注入补齐属性声明；常量用 `dlsym` 从已加载的 UIKit 取真值（16.5 SDK 里没这个导出符号，`UIKIT_EXTERN` 和 `weak_import` 都过不了链接）。上游 `DYYY.xm` 因此保持逐字节不变。SDK 升到 17+ 后该头文件自动失效，可整块删除。另两处 CI 才暴露的坑：**文件被 `-include` 注入时不能直接判 `__IPHONE_OS_VERSION_MAX_ALLOWED`**（那时宏还没定义，判断恒真 → 在 iOS 17+ SDK 上重复声明），必须先 `#import <Availability.h>`；**垫片符号必须 weak 定义**（Apple 工具链的 `libclang_rt.ios.a` 已定义 `__isOSVersionAtLeast`，强定义会撞 duplicate symbol）。
4. **默认 scheme 必须留空**：上游 CI 的 `Build Rootful` 步骤是裸跑 `make package`，靠「不指定 scheme」出 rootful 包。Makefile 里若默认成 roothide，那一步会打出 arm64e 文件名，后续重命名循环与 `packages/*.deb` 排序错位、步骤返回 1（实测踩过）。本机构建统一走 `scripts/build.sh`，它显式传 `SCHEME=roothide`。

### 版本号规则（已核对 theos 源码 + 实测）

`control` 里的 `Version` 是 theos 的**基础版本**；不带 `FINALPACKAGE` 本地打包时会在后面追加构建号（计数落在项目 `.theos` 数据目录）。`build.sh` 每次都 `make clean`，所以版本稳定为 `2.2-9fork2-1`；连续 `make package` 且不清 `.theos` 才会递增成 `-2`、`-3`。上游 CI 走 `GITHUB_ACTIONS=true`（等价 `FINALPACKAGE=1`）得到的是干净的 `2.2-9fork2`。

## 四、安装

```bash
# 设备上（SSH 或终端）
dpkg -r com.lcs.dyui        # 更早的自研插件，装新包前清掉；新包已声明 Conflicts/Replaces，dpkg -i 也会自动移除
dpkg -i /tmp/com.huami.dyyy_2.2-9fork1-1_iphoneos-arm64e.deb
killall -9 Aweme
```

- 入口：**两指长按屏幕**呼出设置页（`DYYY.xm` 的 `%group DYYYSettingsGesture`；开关 `DYYYDisableSettingsGesture` 可关）
- 首次使用需在设置页接受用户协议（`DYYYUserAgreementAccepted`）；未接受时上游 `%ctor` 会拦住大部分功能初始化

## 五、长期维护

### 同步上游

```powershell
git -C D:\xiazai\dsh\dyyy fetch upstream
git -C D:\xiazai\dsh\dyyy log --oneline HEAD..upstream/main     # 先看有什么新东西
git -C D:\xiazai\dsh\dyyy merge upstream/main                   # 冲突只可能出现在构建层的 6 个文件
```

上游若改了自己的 `Makefile`，把新的 `DYYY_FILES` 名单搬进本地 Makefile（保留垫片条目与那三处适配）。同步后跑 `scripts/build.sh` + `scripts/verify.sh`。

### 抖音升版后功能失效怎么查

1. 设备日志：`idevicesyslog | grep DYYY`，或 Console App 过滤 `DYYY` —— 上游在关键路径有 `NSLog(@"[DYYY] ...")`
2. 按上游 `AGENTS.md` 的类路径速查定位失效功能对应的 `%hook`
3. 确认抖音新版本里的类名/方法是否还在（headless 遍历类与方法列表，别靠猜）
4. 改类名 → `scripts/build.sh` → 装包验证

### 真机踩过的铁律（扩展 hook 前先读）

1. **layout 回调里绝不写容器自身 frame、绝不调 `setNeedsLayout`/`layoutIfNeeded`**：抖音的顶栏/底栏父容器是手写 frame 布局，会形成「改高度 → 重排 → 再改」的无限乒乓，主线程被 layout 风暴吃满，表现为**装上就卡死**（`AWEFeedTopBarContainer` / `AWENormalModeTabBar` / `AWEPlayDanmakuInputContainView` 都踩过）。只做幂等赋值（`hidden`/`opacity`/`font`/子视图 frame），值没变就不写。
2. **隐藏 ≠ 重排**：抖音不会重排被隐藏的项，剩余项仍挤在原位（看起来就是「留白」）。DYYY 的做法是自己按容器宽度均分（见 `AWENormalModeTabBar` 的 `visibleButtons` 重排逻辑）。
3. **能不摘就不摘**：`removeFromSuperview` 会打乱抖音自己的布局计算（切视频重建时错位/崩），`hidden = YES` 可逆且视觉等效；但「看不见仍要能点」不能用 `hidden`（会挡 hitTest），用 `alpha = 0.011`。

### 核对二进制里的中文文案（别用 strings）

clang 把含中文的 `@""` 字面量放进 `__TEXT,__ustring`（**UTF-16LE**），binutils 的 `strings`（含 `-e l`）和 `grep` 默认都查不到，会得到「明明改了却没编进去」的假阴性。核对用逐字节计数：

```bash
wsl -d Ubuntu22 -- python3 -c 'data=open("/tmp/dyyy-verify/Library/MobileSubstrate/DynamicLibraries/DYYY.dylib","rb").read(); print(data.count("视频文案加粗".encode("utf-16-le")))'
```

预期计数 = 出现处数 × 架构数（本包 arm64 + arm64e，所以 ×2）。纯 ASCII 的键名/方法名仍在 `__cstring` 里，`strings` 能查。

## 六、历史与待办

### 上一次维护留下的、**没有**带回本仓库的功能

以下两项曾做过、并在设备上装过，但那一版**一开抖音就闪退且原因未定位**，因此这一版从上游原样重来，先把地基做稳：

| 功能 | 实现要点（需要时可重新加回） |
|---|---|
| 设置页居中窗口化 | 新增 `DYYYWindowContainerViewController`（遮罩 + 圆角卡片 + 标题栏 + 键盘避让），`DYYY.xm` 手势组改为以 `UIModalPresentationOverFullScreen` 弹出 |
| 视频文案字体加粗 | 开关 `DYYYBoldDescription`；在 `AWEPlayInteractionDescriptionLabel`（39.6.0 真机诊断确认存在的类）上按 `NSFontAttributeName` 逐段换粗体，幂等 |

### 闪退排查的下一步（如果又遇到）

1. 先确认设备上**没有**旧包：`dpkg -l | grep -iE 'dyui|dyyy'`（两套 DYYY 同时 hook 必崩）
2. 崩溃日志：`ls -t /var/mobile/Library/Logs/CrashReporter | head`，看 `Exception Type`（`0x8badf00d` = 卡死被看门狗杀，`EXC_BAD_ACCESS`/`unrecognized selector` = 代码炸）与 `Thread 0` 顶部帧
3. 无 SSH 时：设置 → 隐私与安全性 → 分析与改进 → 分析数据 → 搜 `Aweme`
4. 需要二分时：`git stash` 掉本地功能改动，只留构建层出一个「纯上游」对照包，对比是否同样崩

### 禁止事项

- `compat/` 只放工具链垫片，不写业务逻辑；SDK/工具链升级后应能整块删除
- 不把实验性改动直接提到 `main`：新功能开分支（`git switch -c feature/xxx`），设备验证通过再合

## 七、与上游的刻意差异：详情页恢复抖音原样

上游的「启用首页全屏」在**作品详情页**上做了两处补偿，实测在抖音 40.6.0 上会与抖音自身的分页网格打架，表现为：进他人主页点开视频后，视频那一屏比页网格矮 83pt（正文下面多一条缝）、文案与右侧按钮的锚点上移，整页观感错乱。本分支的处理：

| 上游行为 | 本分支处理 | 原因 |
|---|---|---|
| `AWEAwemeDetailTableView -setFrame:` 把表格高度向上取整到屏幕高度的整数倍 | **移除该 hook**（`DYYY.xm` 原处留说明注释） | 抖音自己的分页网格是整屏（926），而视频那一屏的 cell 只给"屏幕 − 底栏"（843）；补整后两者错位 83pt，且表格高度受 autolayout 管理、补了会被下一帧改回 |
| `AWEPlayInteractionViewController -viewDidLayoutSubviews` 对非白名单 referString 一律用 `父高 − 底栏高度` | 详情页（响应者链含 `AWEAwemeDetail` / `AWEMixVideoPanelDetail`）按**满高**处理 | 详情页是被 push 进底栏控制器的，页面自身没有首页底栏；再减一次会凭空少 83pt，把文案/按钮锚点顶上去 |

判定谓词：`+[DYYYUtils isInsideDetailPageFromView:]`。首页、搜索、朋友等原有白名单场景一行未改；关掉「启用首页全屏」即完全回到抖音原样。

排查用的诊断开关、实时通道（设备 :8899）与五个运行时补偿参数，都保留在 `feature/detail-fullscreen` 分支上；以后再遇到详情页/全屏布局问题，切回该分支即可继续用（详见该分支的 `DYYYDetailDiagnostics` / `DYYYLiveChannel`）。

### 补充：这套改动为什么会引发「打开图文/动态图闪退」

实测（对上游同款构建做对照验证）：上游原版打开图文/图集帖子正常，而带上本节两处改动后必崩，崩溃形态是
`EXC_BREAKPOINT` → `libswiftCore._assertionFailure` → `_bridgeCocoaString(_:)` → `String.init(_cocoaString:)`
→ `AwemeCore`（栈里**没有** tweak 的帧，属于"改坏了状态、抖音自己的代码炸"）。

成因是上游的 `%hook CommentInputContainerView`（动态绑定到抖音 Swift 类
`AWECommentInputViewSwiftImpl.CommentInputContainerView`，`-layoutSubviews` 里每次布局都跑）：
它的隐藏逻辑拿 `[(UIView *)self frame].size.height == gCurrentTabBarHeight` 作判据，依赖"屏幕 − 底栏"的高度；
而本节把详情页改成**满高**后几何不符，Swift 侧随即踩到类型断言。

处理方式：在 `DYYY.xm` 该 hook 的 `layoutSubviews` 开头加一句
`if ([DYYYUtils isInsideDetailPageFromView:self]) { return; }`——**详情页直接放行**。
这样既保留了本节"详情页恢复抖音原样"的目标，又消除了闪退；该 hook 在其它场景（非详情页）行为不变。
（逻辑上它本就只在详情页生效，所以对详情页放行 = 该场景下不再改动抖音的原生布局，与本节目标一致。）

## 九、硬规则：装到设备上的包必须来自 CI（macOS 工具链）

本机 WSL 的 Linux clang 产出的是**另一种 arm64e ABI 变体**——构建日志里长期挂着这条警告，
之前被当成噪音忽略了：

```
ld: warning: object file … was built with an incompatible arm64e ABI compiler
```

抖音的 Swift 代码在 arm64e 上重度依赖指针签名（pointer authentication），ABI 变体不匹配会让
Swift 侧拿到类型错误的对象，表现为打开图文/动态图帖子时：

```
EXC_BREAKPOINT (SIGTRAP) → libswiftCore._assertionFailure → _bridgeCocoaString(_:)
→ String.init(_cocoaString:) → AwemeCore
```

**结论（务必遵守）**：

- 本地 `scripts/build.sh` 的产物**只用于编译检查**（语法/链接是否通过），**不要装到设备上**
- 需要装设备验证时走 GitHub Actions 的 `build deb` 工作流（macOS runner，与上游发布版同款工具链）：
  - 手动触发：`POST /repos/ali0613/DYYY/actions/workflows/build.yml/dispatches`，body `{"ref":"main"}`
  - 产物 zip 内含三种 scheme 的 deb：`…-rootful.deb` / `…-rootless.deb` / `…-arm64e-roothide.deb`
  - 下载产物 zip 时注意：GitHub 会 302 跳到 Blob 存储，**重定向请求不能带 Authorization 头**，否则 401
- 对照版本：上游 `Wtrwx/DYYY` 的 `DYYY_2.2-9#1687`（提交 `6bdc7c3`）与上游 `main` **是同一个提交**，
  可作为"能用"基准；凡是"上游/CI 构建正常、本地构建崩"的现象，先查上面那条 ABI 警告

> 另：roothide 装包时会把 `Library/...` 落到真实越狱根
> `/var/containers/Bundle/Application/.jbroot-<systemhook 后缀>/Library/MobileSubstrate/DynamicLibraries/`；
> 用同名 `.disabled` 后缀可临时停用某个 dylib（排查是否由 tweak 引起时很好用）。

## 十、直播卡片（信息流里的「直播中」卡片）经验

（2026-10 实录，抖音 40.6.0 / iOS 16.1.1；全部由 FLEX 现场定位得出）

### 视图结构（FLEX 确认）

`IESLiveStackView` 与 `IESLiveLayoutContainerView` **逐层嵌套**（各三四层，"徽标/昵称/文案/底部行"
都是 `IESLiveLayoutContainerView` 行容器）；最外层还有一个**全宽容器**。
两个按钮「点击进入直播间 / 翻转」同属 **`AWELivePrestreamGuideView`**，superview 为 `AWEBaseElementView`。

### 缩放（「昵称文案缩放」在直播卡片上生效）

1. **缩 stack 自身无效** ✗（transform 会被上层布局或自身逻辑改写）；有效的是**行容器**或**包含全部行的最内层 stack**。
2. **`UIStackView` 子树不要用 `UIView.transform`**：stack 会按"缩放后的 frame"重新布局，比例被反复叠加
   （0.8 看起来像 0.5）；要用 **`layer.transform`**（不参与布局）。
3. **必须按对齐方式补偿**（transform 绕中心缩放）：
   - 左对齐内容 → `tx = (w − w×s) / -2`
   - 顶对齐内容 → `ty = (h − h×s) / -2`
   - **居中按钮不能补平移** ✗（补了会被推偏）
4. **时机**：`layoutSubviews` / `didMoveToWindow` 在这个 stack 上**都不触发**；
   可靠入口是**行容器自己的 `layoutSubviews`**（此时宽度已确定）。早期入口会因宽度为 0 被跳过。
5. **cell 复用**：抖音会重写 `setTransform:` → 必须**接管它**，把抖音写入的值当**新基准**并**立刻重应用**；
   否则 (a) 基准过期 → 位置偏移，(b) 要等下次布局 → 划回来能看到"缩放过程"。
   重应用时**位移量要记住**（放在工具层状态里），否则复用后位移被抹掉。
6. **判别目标别看 superview**：同类视图层层嵌套，superview 判断会命中**空 stack（404×0）**；
   要看**实际内容**（如直接子视图里有没有高度 ≤40 的行容器）。

### 相关搜索（直播卡片上不生效的那条）

直播卡片的「相关搜索」**没有专属类名** ✗ —— 整条链都是通用类
（`IESLiveLayoutContainerView` → `AWEBaseElementView` → `UIView` → `UILabel`），
只能**按文字内容识别**（行高 30~50 且内部 `UILabel` 以「相关搜索」开头），复用既有开关 `DYYYHideInteractionSearch`。

### 整块上移（让开底栏）

复用「首页全屏化」那套：上移量 = **`gCurrentTabBarHeight`**，条件跟随 `DYYYEnableFullScreen`，**不额外加设置项**。

## 十一、文案字体加粗（补充）

抖音 40.x 的文案是 **`YYLabel` 系**（layer 为 `YYTextAsyncLayer`）：改 `font` 属性**不生效** ✗，
必须**重建 attributedText**（用 `addAttribute:` 只换字体，保留话题高亮等属性；已粗体则跳过 → 幂等）。

且字体名是 **`.SFUI-Regular`（苹果私有名）** —— `fontDescriptorWithSymbolicTraits:` 对它
**只会返回同款常规体** ✗（不报错也不变粗）。必须直接指定字体名 **`PingFangSC-Medium`**（真机 FLEX 实测），
否则用 `boldSystemFontOfSize:` 兜底。

> 文案有两处 hook（`AWEPlayInteractionDescriptionLabel` 与 `AWEPlayInteractionDescriptionScrollView`），
> 绑定时机不固定：setter 负责"先赋值"的顺序，`layoutSubviews` 负责"抖音后赋值覆盖"的顺序，两道都要有。

> ⚠️ **硬规则（fork73 起）**：这里说的"重建 attributedText"**必须建立在 `self.attributedText` 之上**（`mutableCopy` + 只 `addAttribute:` 换字体）。
> 曾经有一版是**从纯文本 `self.text` 重新构造**整份富文本：文字、颜色看着都正常，但话题/@/搜索词的**区间属性被整份丢掉** →
> **文案标签点了没反应**。事故全过程与教训见第二十一节。

## 十二、本地出包（**取代第九节的"只能靠 CI"结论**）

**结论：本地可以出可直接安装的包，一轮 1~2 分钟，不需要推 CI。**

### 原理

之前判定"本地包不能用"，根因**只在 `arm64e` 那一片**：
Linux 侧 clang 编出的 arm64e 目标文件与 iOS 的 arm64e ABI 版本不兼容
（`ld: object file … was built with an incompatible arm64e ABI compiler`），装上去会崩。

而**抖音是 App Store 应用 = 纯 `arm64`**（arm64e 只有系统进程用），所以：

```bash
bash scripts/build-local.sh arm64            # 只编 arm64 → 无 ABI 问题、可直接装
bash scripts/build-local.sh arm64 install    # 编完自动 scp 进设备 + dpkg 安装 + 重启抖音
bash scripts/build-local.sh both             # 需要双架构时才用（这个包不要装到设备上）
```

- 包标记仍是 `iphoneos-arm64e`（Sileo 认 ✓），但**二进制只有 arm64** ✓ —— 抖音里注入正常 ✓（实测 ✓）。
- 包体积约为双架构包的一半（少了一片），属正常现象。

### 设备免密（一次性）

设备装 `openssh` 后，把 WSL 侧的公钥追加到设备：

```bash
# 公钥：packages/wsl_key.pub（脚本已生成，对应 WSL 的 ~/.ssh/id_ed25519）
scp packages/wsl_key.pub root@<设备IP>:/tmp/
ssh root@<设备IP> 'mkdir -p $HOME/.ssh && chmod 700 $HOME/.ssh && cat /tmp/wsl_key.pub >> $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys && rm -f /tmp/wsl_key.pub'
```

- **注意 1**：Windows PowerShell 不支持 `<` 重定向 ✗（用 `scp` 传文件，别用管道 ✓，管道会带 CRLF 进密钥文件 ✓）。
- **注意 2**：**免密只在配了公钥的那一侧生效** —— 在 Windows 上验证会仍要密码（Windows 的 `~/.ssh` 是另一套密钥），
  要用 WSL 侧验证：`ssh root@<IP> 'echo ok'`。
- **注意 3**：从本工具（pwsh 外壳）调用 WSL 时，命令行里的 `$XXX` 会被 PowerShell 提前展开 ✗ →
  **要么写成脚本文件再执行，要么用 `~` 代替 `$HOME`**（本项目就是这么踩过来的 ✓）。

### 自动化下一步

需要"改完直接装机"时用 `install` 模式即可；`Makefile` 的 `INSTALL=1 THEOS_DEVICE_IP=<IP>` 亦可（等价能力）。

## 十三、未解决：横屏自动翻转往返后元素错乱（已留下现场证据）

**现象**：开启「启用首页全屏」时，**冷启动后第一次**"自动翻转成横屏 → 自动翻回竖屏"会让首页元素整块错乱；
**下滑几个视频即自愈**。手动点翻转按钮不触发；关掉「启用首页全屏」也不触发。

**已定位的事实**（靠祖先链诊断，见下）：

```
[元素] AWEBaseElementView            {774.67, 0}  32×32
  ↑0   AWEElementStackView           {59.67, 489} 806.67×32     ← 宽 806 ✗
  ↑1   AWEDPlayerInteractionView     926×428                     ← 横屏尺寸 ✗
  ↑5   AWELandscapeMediumVideoPlayerCell 926×428                 ← 抖音没把它改回竖屏 ✗
  ↑6   UICollectionView              428×926                     ← 父级早已是竖屏 ✓
```

即：翻回竖屏后，抖音的**横屏播放器 cell 仍保持横屏尺寸**，其下所有元素于是全按横屏坐标排（x≈806，而竖屏只有 428 宽）。

**已试过但无效的修法**（都不要再重复走）：

1. 横屏期间不干预 `transform`；
2. 横屏时把「全屏化」的布局调整整体停用（总闸 `isFullScreenAdjustEnabled`）；
3. 按窗口尺寸摆正"最外层仍为横屏尺寸"的容器 + `setNeedsLayout`/`layoutIfNeeded`；
4. 监听方向变化、主动踹一次窗口布局；
5. 抖动宿主 `UICollectionView` 的 `contentOffset` 1pt（同帧弹回）。

**关键教训**：真正能自愈的是**滚动所触发的"cell 重新配置"**，普通布局重排（`setNeedsLayout` / `layoutIfNeeded`）
**不足以**让抖音重新配置该 cell —— 下次接手从这里查：例如复现真实滑动、或查"首次翻转"那一次 cell 配置为何用了横屏尺寸。

**诊断手法（可复用）**：在元素布局里检测"竖屏下元素被摆到窗口右边界之外"，把该元素**整条祖先链**
（每层的类名 + frame + bounds）写进 `NSTemporaryDirectory()/dyyy-chain.txt`，再用 SSH 取回：
`find /private/var/mobile/Containers/Data/Application -name dyyy-chain.txt`。

## 十四、昵称文案缩放（首页左块）：判据长什么样 + 「无文案视频不生效」的根因（已修）

**判据在哪**：`%hook AWEElementStackView -layoutSubviews` —— 先用 `AWEPlayInteractionViewController` 过滤，
再把 stack 归类成左块/右块，只有归类成功才套 `DYYYNicknameScale` / `DYYYElementScale`。

| 归类 | 判据（`||`，任一命中即可） | 依赖的内容 |
|---|---|---|
| 右块<br>`DYYYElementScale` | ① a11y 标签 == `"right"`<br>② 含 `AWEPlayInteractionUserAvatarView`<br>③ 子元素 `elementClassName == AWEPlayInteractionUserAvatarOptElementElement` | **头像 —— 每条视频都有** ✅ |
| 左块<br>`DYYYNicknameScale` | ① a11y 标签 == `"left"`<br>② 含 `AWEFeedAnchorContainerView`<br>③ 子元素 `elementClassName` 含 `AWEPlayInteractionStandardAuthorElement`（fork65 新增）<br>④ 子元素 `elementClassName == AWEPlayInteractionDescriptionElement` | **作者信息（昵称就在里面）—— 一直有** ✅<br>（仅 ④ 时：文案 —— **可能没有** ❌） |

**判据出处**（`git log -S` 可复现）：
- 上游 `079d3734`：原本**只有 a11y 标签**；
- huami `4755743`「修复新版本右侧文案缩放失效」：加了头像判据 ②③；
- huami `3f540dd`「修复新版本描述文案缩放失效」：加了**文案元素**判据 ④ —— 坑就是从这里来的。

**为什么无文案视频不生效**（2026-10 一次性诊断，`dyyy-left.txt` 共 37 个结构快照）：

- 40.6.0 里这套 stack 的 a11y 标签**恒为空**（37 次采样 `a11yL=a11yR=0`、`anchor=0`，全 miss）→ 老判据 ①② 是死路；
- 有文案左块 = `时间属地 + 文案 + 作者信息 + 弹幕`（4 个子元素）→ 命中 ④ ✓
- **无文案左块 = `时间属地 + 作者信息`（只有 2 个子元素，文案与弹幕元素都不在）** → 判据全 miss
  → `isLeftStack` 恒 NO → `if (isRightStack) {} else if (isLeftStack) {}` **两个分支都不进**
  → 整段缩放逻辑一行都不执行（连 transform 重置都没有）。
- 右块从来没有这个毛病，因为它的判据是**头像**（与内容无关）——**左右判据不对称才是根因**。

**修法（fork65）**：左块判据补 ③ `containsString:@"StandardAuthorElement"`（昵称就在该元素内部，与视频内容无关）；
用 `containsString` 而不是等号，因为抖音同类元素名有带后缀的变体（如 `...UserAvatarOptElementElement`），
等号匹配一旦改名就**静默失效**。同时删掉同类的 `-arrangedSubviews` hook（判据只有 a11y+锚点，实测恒 miss = 纯死代码，
而且和 `layoutSubviews` 里的判据重复，容易两处打架）。

**刻意没做**：加"未识别就重置 identity"的兜底 —— 底部栏/合集那些 stack（`a11y=「bottom」`、`AWEPlayInteractionNewMixVideoInfoElement`）
本来就不该被我们写 transform，盲重置可能和抖音自身的变换打架。若日后出现"缩放在复用的 stack 上残留"，
再改成**只重置自己缩过的 stack**（associated object 打标）。

**可复用的诊断手法**：在这个 hook 里按「结构签名 = stack 指针 + 子视图数 + 关键元素有无」去重，
把每个 stack 的 a11y 标签、四条判据命中情况、每个子元素的类名 / `elementClassName` / frame / hidden / 文本
写进 `NSTemporaryDirectory()/dyyy-left.txt`（每进程首次写入用 `"w"` 清空）。
**关键点：有文案 / 无文案各打开一次**，两份一对比缺哪个元素一目了然。
⚠️ 诊断块要放在"判据算完、应用之前"，此时 `transform.a` 还是上一轮的值 —— 看到 1.000 **不代表**没生效。

## 十五、硬编码 `-20` 与「预直播页」分支：实测判定并拆除（fork66）

**背景**：`%hook IESLiveStackView -layoutSubviews` 里有一段以 `AWELiveNewPreStreamViewController` 为条件的处理，
它**先**算 `currentScale / tx / ty`（含全屏化的 `ty -= gCurrentTabBarHeight`），**再**把结果整个覆盖成
`translation(0, -20)` —— 算出来的值一个都没用上。

**判定手法**：临时探针（三站点，写 `tmp/dyyy-pre.txt`，按 site+类名去重）。实测两行：

```
A:IESLiveStackView.layoutSubviews  vc=<AWELiveNewPreStreamViewController> 预直播类=命中
   bounds={{0,0},{404,926}}  transform=[1, 0, 0, 1, 0, 0]
B1:预直播分支(IESLiveStackView)     vc=<AWELiveNewPreStreamViewController> 预直播类=命中
   bounds={{0,0},{404,926}}  transform=[0.80000001, 0, 0, 0.80000001, -32.319998, -74.079997]
```

**四条结论**：

1. **这段不是死代码，它真的在跑**（A / B1 双命中），`AWELiveNewPreStreamViewController` 这个类在当前版本存在。
2. **影响面就是首页那张直播卡片**：`404 = 428 − 左右各 12pt`（卡片宽度，整页是 428）——
   即**首页信息流的直播卡片是被 `AWELiveNewPreStreamViewController` 承载的**，不是"某个没去过的页面"。
3. **旧的注释「本类 layoutSubviews / didMoveToWindow 都不触发」是错的**（A 实测命中）。这条错误前提以前影响过判断，
   已在两处 `setAlpha:` 注释里就地改正。
4. **"我们写好 → 它抹掉"是真实发生的**：B1 进入时 transform 已是缩放值，紧接着被覆盖成 `(0,-20)`；
   每趟布局一次 → 谁最后写谁生效，这就是历史症状「划过去划回来会看到缩放过程」「位置还是有问题」的机制。

**顺带证据**：B1 那个 transform 的 `tx/ty` 是用 **0.8 倍的尺寸**（323.2 × 740.8）算出来的
（`(323.2−258.56)/−2 = −32.32`、`(740.8−592.64)/−2 = −74.08`），正是第十节记的
「transform 参与布局 → 比例被反复叠加」的现场实例。

**处理（fork66）**：**删掉这段分支**（连同探针与 `-20` 写入）。位移只保留
`applyLiveCardScaleToStack:`（`shiftUp` 参数）**一处来源**。
⚠️ 以后这张卡片整体偏高/偏低，只改 `shiftUp` 那一处，**不要**再往 hook 里加 transform 写入。

## 十六、「右侧栏上移」漏到左块：push 转场把左块元素伪装成右半屏元素（fork67 修）

**现象**：**从观看历史（或任何 push 进入的页面）点开视频**时，左下「昵称 / 文案 / 时间属地」整块**偏上约 10pt、
下方多出一段空白**；而且**一直不自愈**，必须滑走再划回才恢复。首页信息流的纵滑不会出现。

**判据在哪**：`%hook AWEBaseElementView` 的 `setFrame:` / `didMoveToWindow` / `layoutSubviews` 三处入口，
原本条件是「元素在窗口里的 `x ≥ 屏宽一半`」就写 `transform = translation(0, -DYYYElementShiftUp)`（本机 10）。

**根因**：push 转场时新页面**从屏幕右侧滑入**，左块元素（页面内 x=12）在窗口里的 x 会一路从 440 滑到 12 ——
当 x ≥ 214 时**它看起来就是个右半屏元素**，判据被骗、写下 -10；而这是一次性写入、之后没人撤销 →
于是"偏上 + 下方留白 + 不自愈"。（首页是纵向滑动，x 恒为 12，所以永远骗不过判据。）

**证据一（元素级窗口坐标实测）**：左块四个元素**整体上移 8.0pt**
（`736.3−728=8.3`、`768.3−760=8.3`、`797.1−789=8.1`、`825.9−818=7.9`），而 `8 = 10 × 0.8`
（容器缩放的 0.8 一乘）；元素之间的**相对距离完全正确** → 说明是"整块平移"，不是某个元素自己跑偏。

**证据二（探针实录 `dyyy-shift.txt`）**：

```
accept            win={364.0, 499.5  64.0x68.0}   ← 右栏正常命中（x=364，右边缘 428）
reject-左半屏      win={ 12.0, 741.1 250.4x32.0}   ← 左块正确跳过
reject-越界(转场)  win={440.0, 907.1 250.4x16.8}   ← ★元凶现行：宽 250.4 = 缩放后的左块，转场中 x=440
heal-撤销误写      win={  0.0,  17.0  50.0x84.0}   ← ★自愈命中，撤掉了已写下的残留
```

**修法（fork67）**：判据与自愈收拢到 `DYYYUtils applyRightColumnShiftIfNeeded:`（三处入口共用同一份，改一处即可）：

1. 判据补一条「**右边缘不越界**」（`x + w ≤ 屏宽 + 1`）：转场中的左块元素在 x ≥ 214 时右边缘必然 ≥527 > 428 → 被挡住；
2. 给写过的元素**打标**（associated object），之后判为"不是右栏元素"时，**只要 transform 逐位等于我们当初写的值**
   就撤销它 —— 既自愈残留，又不可能覆盖抖音自己的变换/动画值。

**（fork71 更新）**：本节描述的"三处入口 + 越界判断 + 打标自愈"**已整段删除** ——
位移改为在 `%hook AWEElementStackView` 的右栏分支里**一次写入**（写在容器自己的 transform 上），
所以 `DYYYUtils applyRightColumnShiftIfNeeded:` 这个方法现在**不存在了**。原因见第十九节。

**教训（可复用）**：

- 用**窗口坐标**做几何判据时，必须同时检查"**整体在屏幕内**" —— 否则**转场/滑入动画**会让元素的坐标短暂出现在任何位置；
- 这类判据的**时机**比判据本身更危险：`setFrame:` / `didMoveToWindow` / `layoutSubviews` 在转场期间都会跑；
- **一次性写入的 transform 没有撤销机制 = 症状永久化**：凡是我们"写上去就不再管"的几何值，都要配一套打标 + 自愈。

## 十七、「次要文字」透明度统一（fork69）

时间属地整行、进度时长（左/右）统一挂常量 `kDYYYSecondaryTextAlpha = 0.6`（`DYYY.xm` 顶部 statics 区）——
以后要统一调这一档，只改常量一处即可。

**⚠️ 改进度时长时注意：它有【两份实现】，改一份只生效一半场景**：

| 实现 | 谁在用 |
|---|---|
| `%hook AWEFeedProgressSlider` 的 `dyyy_updateScheduleLabelsWithCurrentTime:totalDuration:` | 首页进度条 |
| `UIView (DYYYProgressLabelLegacy)` 的 `dyyy_updateScheduleLabelsLegacyWithCurrentTime:totalDuration:model:` | `AWEPlayInteractionProgressController`、`AWEDProgressCoreContainer` |

两份都是"在父视图上按 tag `10001`/`10002` 建/复用左右标签"，样式（字体 8、颜色取 `DYYYProgressLabelColor`、透明度取上面的常量）
**每次更新都写一遍**（幂等，防被重置）。所以：改样式要**同时改两份**，否则换个页面就"没生效"。

> 另外记一条叠加规则：若「进度时长颜色」本身带透明度，最终会再乘一次 0.6（时间属地同样规则，两边一致）。

## 十八、「汽水音乐提醒」条随机漏：靠"钓鱼探针"抓到真实类名与失败原因（fork70 修）

**问题特征**：`%hook AWEBaseElementView -layoutSubviews` 里那句「子视图类名含 `DiversionBar` → `hidden = YES`」
**有时不生效**，而且**只在首页随机刷到时才复现**，没法主动重现。

**办法：改成"钓鱼"（被动捕获），不用复现** —— 在三个必经入口布只读探针，命中即记录并**自动截图**：

| 入口 | 判据 |
|---|---|
| `AWEBaseElementView -layoutSubviews` | 类名 / 文字 |
| `UILabel -setText:`（**必须扩展已有 hook，不能再开一个 `%hook UILabel`**，否则 redefinition 编译失败） | 文字含「汽水音乐 / 懂你想听」 |
| `UIView -didMoveToWindow` | 只查类名（热路径保持便宜） |

命中时写 `tmp/dyyy-soda.txt`（**追加、不截断** —— 随机问题必须跨"抖音重启"保留）+ 抓 `tmp/dyyy-soda-N.png` 截图；
另外记录候选类的 `setHidden:` 调用留痕，用来区分「**没匹配到**」与「**匹配到了又被显示回来**」。

**抓到的结论（`dyyy-soda.txt`）**：

```
=== #2 [src=UIView.didMoveToWindow] hit=<AWEPlayInteractionDiversionBar> hid=0
    ↑1 AWEBaseElementView … | ↑2 AWEElementStackView …            ← 父视图确实是元素层
[setHidden] AWEPlayInteractionDiversionBar hidden=0 …             ← 抖音把它「显示」
[setHidden] AWEPlayInteractionDiversionBar hidden=1 …             ← 之后又被「隐藏」
```

1. 真实类名 = `AWEPlayInteractionDiversionBar` —— 也就是说 **`containsString:@"DiversionBar"` 一直匹配得上，问题不是名字猜错**；
2. 父视图确实是 `AWEBaseElementView`、再上是 `AWEElementStackView` —— 原方案方向没错；
3. **失败原因是时机**：抖音会**反复**调 `setHidden:NO` 把它显示回来，而我们只在"element 的那一趟 layoutSubviews"
   里写一次 `hidden = YES`，那一刻之后**没有任何入口纠正**（该 element 未必再布局）→ 被显示回来就**永久露头**；
4. 它还横跨"父 element **未布局 0×0** / **已布局 428×40**"两种出现时机，我们只兜住了后者。

**修法（fork70）**：按本仓库已验证过的解法（同 `AWEFeedAnchorContainerView`）**接管 `setHidden:`**：

```objc
%hook AWEPlayInteractionDiversionBar
- (void)setHidden:(BOOL)hidden { %orig(开关注解 ? YES : hidden); }   // 任何"想显示"都改成隐藏
- (void)didMoveToWindow { %orig; if (开关) { self.hidden = YES; … } } // 进窗口就按下去，不给闪一帧的机会
- (void)layoutSubviews { %orig; if (开关) { self.hidden = YES; … } }  // 幂等再兜一次
%end
```

**外加"塌行"避免留白**：隐藏条形**不会**让它那一行的高度消失（UIStackView 里只有**行本身**被隐藏才会塌），
所以 `DYYYUtils hideDiversionBarRowIfNeeded:` 在**「这一行除 DiversionBar 外没有别的可见内容」**这一保守条件下，
连父 `AWEBaseElementView` 一起 `hidden = YES` → 不留空白且不误伤正常元素行。

**可复用教训**：

- **随机出现的 UI 问题 → 布"钓鱼"探针 + 命中自动截图**，比反复手动复现高效得多；日志要**追加不截断**；
- 判"没匹配到"还是"被改回去"，就**记录对方的 `setHidden:` 调用**（一行留痕即可定位）；
- **一次性写入的 `hidden` 同样会被抖音改回去** —— 和第十六节 `transform` 那条是同一类问题：
  「我们写一次就不管」= 迟早被覆盖，正解是**接管 setter**（`setHidden:`）。

**验收结果：位置没有任何变化** —— 这符合预期，而且能用那份日志直接算清楚原因：

`applyLiveCardScaleToStack:` 里是 `CGAffineTransformConcat(平移, 缩放)`，**平移先作用、随后整体被缩放**，
所以最终 `tx' = tx × 0.8 = −40.4 × 0.8 = −32.32`、`ty' = ty × 0.8 = −92.6 × 0.8 = −74.08`
（`tx`/`ty` 由 `bounds = 404×926`、`base = identity`、`shiftUp = 0` 算出）—— 与日志里那串
`[0.8, 0, 0, 0.8, −32.32, −74.08]` **完全吻合**。

结论：**真正最后生效的一直是我们自己的写入**；`-20` 只在布局帧里短暂赢过一次，随即被
`setAlpha:` / `didMoveToWindow` 那几条入口盖掉。所以删掉它**画面不动**，但"中途把缩放抹掉一帧"的抖动来源消失了。

## 十九、「右侧栏上移」从"右半屏逐元素"收敛为"右栏容器一次写入"（fork71 修）

**起因**（用户原话）：加这个上移是为了解决**右侧栏底部数字与进度时间重叠**，但"因为加了它衍生成许多小问题"。
第十六节那一整套（越界判断 / 打标 / 自愈 / Comment 排除）**全都是为了让一个几何判据不误判而打的补丁** ——
补丁越多，越说明判据选错了层次。

**先把几何量清楚（都是现场 dump 的窗口坐标，428×926、底栏 83）**：

| 锚点 | 实测值 |
|---|---|
| 左/右栏**底边**（缩放到 0.8 后仍钉在这条线上） | **842.67** |
| 进度条那一行的**顶边** | **843.67** |
| 内容底线 = 底栏顶（926 − 83） | 843 |

进度时长标签是**我们自己加的**：`labelYPosition = 进度条顶边 + DYYYTimelineVerticalPosition`（默认 −12.5，本机 −12），
盒子高 15、字号 8 → **文字实际占 835 ~ 843**，也就是**扎进右栏底下 7.5pt**；把右栏抬 8pt
（`10 × 0.8`，见第十六节的窗口坐标实测）刚好让开 —— **"上移 10 刚好够"不是巧合，是 8 ≈ 7.5**。

原版抖音平时**不**显示时间文字（我们那个开关的描述就是"**强制**显示所有视频的进度条和时长"），
所以它敢把右栏底边钉死在内容底线上。**这 1pt 的地盘是我们自己挤出来的。**

**关键结论：几何上只有"谁让位"两种可能，没有第三条路**（两者只差 1pt）：

- **让位方 = 我们的标签**（把它挪到进度条行内/下方，或只在拖动时显示）→ 右栏根本不用动，位移设置可以删；
- **让位方 = 右栏**（现状）→ 那么"怎么让"必须只写一次、且写在该写的那一层。

**修法（fork71，本轮采用后者）**：位移并入 `%hook AWEElementStackView` 右栏分支**那一次** transform 写入：

```objc
if (isRightStack) {
    self.transform = CGAffineTransformIdentity;          // 先归零，下面读到的才是未变换基准
    const CGFloat shiftUp = DYYYGetFloat(@"DYYYElementShiftUp");
    CGFloat scale = (配置了 DYYYElementScale 且 >0) ? 值 : 1.0;
    if (scale != 1.0 || shiftUp != 0.0) {
        … ty = Σ(h − h×scale)/2; right_tx = (W − W×scale)/2;   // 原缩放计算（钉住右下角）
        ty -= shiftUp * scale;                                  // ★ 上移折进来，同一次写入
        self.transform = CGAffineTransformMake(scale, 0, 0, scale, right_tx, ty);
    }
}
```

同时**删除**：`%hook AWEBaseElementView` 的 `setFrame:` / `didMoveToWindow` 两个方法与三处调用、
`DYYYUtils applyRightColumnShiftIfNeeded:` 整个方法、文件静态量 `gDYYYRightColumnShiftApplying`、
头文件声明。（该 `%hook` 只保留「隐藏去汽水听」的兜底层，见第十八节。）

| 事项 | 说明 |
|---|---|
| **有效位移** | `shiftUp × scale`：旧写法写在元素上会被容器 0.8 再乘一次（设 10 → 实际 8pt），**乘 scale 才能逐像素不变**。要改观感请改设置值，别删这个乘数。 |
| **判据** | 右栏身份改由**结构**决定（a11y `"right"` / 含 `AWEPlayInteractionUserAvatarView` / 含 `AWEPlayInteractionUserAvatarOptElementElement`），**完全不再看坐标** → push 转场再也骗不过它。 |
| **撤销机制** | 不需要了：每次布局都由这里重写（幂等）。"写了撤不掉"这个病根随写入方式一起消失。 |
| **刻意的收窄** | 不再影响"落在右半屏、但不在右栏容器里"的元素（旧判据会顺手把它们也抬 8pt）。若发现屏幕右侧别的东西比之前低 8pt，就是这一类 —— 它本来也不该跟着右栏动。 |
| **观感** | 应当**完全不变**（同一容器、同一有效位移 8pt）。 |

**可复用教训**：

- 能**用结构/身份判定**时，绝不用**几何/坐标判定** —— 后者在转场、复用、动画期间必然出现"短暂满足条件"的假阳性，
  而每一个假阳性都要靠"补丁 + 自愈"去兜，补丁会越滚越多；
- **补偿性变换要写在"能表达意图的那一层"**（右栏容器），而不是"能碰到的每一层"（每个元素）：
  写在容器上 → 整栏一起动、可幂等重写、不需要撤销机制；
- **一次性写入的几何值 = 迟早要配自愈机制**（§16 的 `transform`、§18 的 `hidden` 都是同一类病）。

## 二十、「隐藏评论视图」藏了内容却留一条空白带：高度是 IGListKit 的 section 给的（fork72 修）

**现象**：打开「隐藏评论视图」后，评论区顶栏的内容（定位卡「XX市 · N万人打卡」等）确实没了，
但**顶部留一条约 61pt 的空白带** —— 位置在 ⤢/✕ 按钮行与「评论 903 ｜ AI 解析」之间。

**排查过程（五轮探针，每轮只加"下一个未知量"的采集，全部只读、不动视图）**：

| 轮次 | 探针看到的关键事实 | 结论 |
|---|---|---|
| diag6 | 我们 hook 的 `CommentHeaderTemplateAnchorView` 已 `hidden=1`，它的父"行"也 `hidden=1`，但 `CommentPanelHeaderNewCell`（UICollectionViewCell）仍是 `win={0, 296.3 428x61} hidden=0` | 留白 = **格子的高度**，不是内容 |
| diag7 | cell 内那一行有 `UIView.8 == nil.0 +61.0`（绝对高度约束）；把它置 0 后 dump 里**仍是 61** | 约束被 Swift 侧每次布局重写 → 从外面改等于对着干 |
| diag8 | `preferredLayoutAttributesFittingAttributes:` **确实被调用**（说明 cell 是自适应型）；我们改 0 后 `systemLayoutSizeFitting` 已经是 `0x0`，但 `attrs[s0,i0]` 仍是 61；`dataSource=IGListAdapter`；类名单里出现 `…CommentPanelHeaderSectionController` | 高度由 **IGListKit 的 section controller** 决定，cell 的意愿不算数 |
| diag9 | hook `sizeForItemAtIndex:` 返回 **0** → 留白消失 ✓，但**评论列表整块不渲染**（主 collection view 子视图 5→3，`AWETabContainerSectionCell` 压根没被创建） | **0 高 = "这一项是空的"**，会被框架静默丢掉 |
| diag10 | 改成 **0.5pt** → 列表回来、留白消失；`子 AWEBaseListSectionBackgroundView win={0, 296.3 428x0.5} hidden=0` | 剩下的**细横线 = 该 section 的"底色视图"** |

**最终修法（fork72）**：

```objc
// ① 谁算尺寸就改谁：IGListKit 的 section controller
%hook AWECommentPanelHeaderSwiftImpl_CommentPanelHeaderSectionController
- (CGSize)sizeForItemAtIndex:(NSInteger)index {
    CGSize size = %orig;
    if (DYYY开关) { size.height = 0.5; }   // ⚠️ 不能是 0（0 会让评论列表整块不渲染）
    return size;
}
%end

// ② 压扁后随它一起缩的"装饰视图"要一起处理：section 底色只剩 0.5pt 却还在画 → 一条细横线
%hook AWEBaseListSectionBackgroundView
- (void)layoutSubviews {
    %orig;
    if (DYYY开关 && self.frame.size.height < 1.0) { self.hidden = YES; }
}
%end

// ③ 还有一条"孤儿分隔线"：抖音自己的列表顶部分隔线是普通 UIView（不在 collection view 里），
//    位置按它假设的头部高度算 —— 头部压掉后它留在原地，穿在评论列表中间。
//    它每次布局都会被抖音重新摆回去 → 由面板的 viewDidLayoutSubviews 每趟按下去。
%hook AWECommentContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    [DYYYUtils hideCommentPanelHairlinesInView:self.view];   // 高≤1pt + 宽≥屏宽60% + 上半屏 + 半透明底色
    ...
}
%end
```

> **diag11 的取证**（改前先量）：`thin UIView win={0, 383.8 428.0x0.50} bgAlpha=0.12 parent=UIView`
> —— 普通 UIView、0.5pt 高、12% 不透明度的填充、父视图也是普通 UIView（不在 collection view 里）
> ⇒ 与抖音的布局体系无关的一条**独立分隔线**，只能靠"每次布局后按下去"解决。

保留（有用）：`DYYYUtils collapseRowIfEmpty:`（藏掉"已空掉的那一行"+ 置 0 绝对高度约束）、
`CommentHeader*` / `AWEPOIEntryAnchorView` / `AWECommentGuideLunaAnchorView` / `AWEShowPlayletCommentHeaderView` 的 `setHidden:` 接管、
`hideCommentPanelHairlinesInView:`。
删除（实验/残留）：`preferredLayoutAttributesFittingAttributes:` 钩子、`dyyy_dumpCommentTopAreaToFile:` /
`dyyy_appendDiagLine:` / `dyyy_dumpThinLinesToFile:` 及全部探针，
外加**一处历史残留探针**（`AWEFeedVideoButton` 里往 `tmp/dyyy-user.txt` 写 200 行的那段 —— 每次启动都写，属于该清的垃圾）。

**可复用教训**：

- 列表项的**高度有三个可能的主人**：① 内容约束（cell 自适应）② cell 的自适应接口 ③ **列表框架的 section 尺寸**。
  前两个"看起来生效了"（`systemLayoutSizeFitting` 都 0 了）**也不代表布局会变** ——
  **先确认是谁算的尺寸，再动手**：`collectionView.dataSource` 的类名（这里是 `IGListAdapter`）+ 类名单里带 `SectionController` 的那个，就是答案；
- **"0" 是危险值**：0 高/0 尺寸常被框架理解成"这一项不存在"而静默丢弃（评论列表整块消失）。
  留 `0.5pt` 这种"**非零但不可见**"的值，语义与视觉两头都保住；
- **压高度时要顺带想到随它一起缩的装饰视图**（section 底色、分隔线）：主体藏了，"发丝线"还在；
- 探针**分轮递进**比一次全量 dump 更快锁定真身：这轮 5 次出包，每次都在缩小包围圈；
- **"身首分离"要多想一层**：我们把"头部"的高度拿掉时，**不在同一套布局体系里**的元素（这里是抖音自己画的
  分隔线，靠它自己对头部高度的假设定位）不会跟着走，会变成"孤儿"留在画面里 ——
  这类元素没法一次性解决，只能**在每次布局后按下去**（`viewDidLayoutSubviews` + 紧判据）。

## 二十一、文案标签点不动：加粗时"从纯文本重建富文本"把区间属性整份抹掉了（fork73 修）

**现象**：开着「文案字体加粗」时，视频文案里的 `#话题#` / `@昵称` / 搜索词**点了没反应**（不跳转）；
文字本身、颜色、行距看着都正常 —— 所以很难联想到是加粗引起的。

**根因**：抖音 40.x 的文案是 `YYLabel` 系，**"这一下点在不在高亮上"由富文本里挂在字符区间上的属性决定**（`YYTextHighlight`）。
而「文案加粗」在 2026-10-05 重做时走了一条**把富文本整份重建**的路：

| 时间 | commit | 干了什么 |
|---|---|---|
| 10-05 18:17 | `ba8b586` | 诊断版 1：只写 `self.font`（无害，但 YYLabel 不认） |
| 10-05 18:29 | **`968a35d`** | 诊断版 3：改成 `[[NSMutableAttributedString alloc] initWithString:self.text]` ← **区间属性从这里开始被抹** |
| 10-05 18:54 | `042b036` | 「正式版」换 `PingFangSC-Medium`，**把重建那一步一起留下了** |
| 10-05 19:36 | **`558c81f`** | 补 `layoutSubviews` 二次确认 → **每趟布局都再抹一次**，抖音想恢复也恢复不了 |

被抹掉的不只是高亮：段落样式、链接属性同样没了（只是看不出来，所以没人怀疑）。
第十一节早就写着"**保留话题高亮等属性**"—— **实现和设计意图正好相反**。

**修法（fork73）**：`dyyy_directBoldFont` 改为以 `self.attributedText` 为基准 `mutableCopy`，只覆盖 `NSFontAttributeName`：

```objc
NSAttributedString *dySource = self.attributedText;   // 抖音刚写进去的那份（含高亮）
if (dySource.length == 0) { /* 只有"抖音写了纯文本"时才退回 self.text + textColor */ }
UIFont *dyFont = self.font ?: [dySource attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
if (dyFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) return;   // 幂等
NSMutableAttributedString *dyAttr = [dySource mutableCopy];
[dyAttr addAttribute:NSFontAttributeName value:dyBoldFont range:NSMakeRange(0, dyAttr.length)];
self.attributedText = dyAttr;   // 高亮 / 段落 / 链接属性全部保留
```

**为什么敢去掉"重建"**：真正让文案变粗的是**字体名 `PingFangSC-Medium`**（第十一节的 FLEX 实测结论），
"从纯文本重建"只是当天诊断期的副产品 —— 它换的也只是字体属性，却顺手把别的属性一起丢了。

**可复用教训**：

- **富文本不是字符串**：`initWithString:` 重建 = 静默丢掉全部区间语义（高亮 / 链接 / 段落），
  而**视觉上通常看不出来**（文字一样、颜色照抄 `textColor`）—— 这类 bug 只能靠"改前先问一句：还有谁在读这些属性"来防；
- **症状离凶手很远**：报告是"标签点不动"，凶手却在"字体加粗"里。**把改动时间线和症状出现的时间对齐**是最快的定位手段
  （本次：前一天 18:17~19:36 重做加粗 → 次日报告点不动，四个 commit 全在 3 小时内）；
- **诊断期的"临时手法"必须回头审**：`ba8b586` / `968a35d` 的提交信息里都明写"临时 / 定位后恢复"，
  但"临时"的那行代码活到了正式版。**临时手段要么显式记账，要么在恢复开关时连同手法本身一起复核**；
- 定位手法本身可复用：先**读设置**排除"故意做坏"的开关（`DYYYLabelStyle` / `DYYYDescriptionVerticalOffset` 都是未设置），
  再让用户**关一个开关复现一次**（0 成本 A/B），比出探针包快得多。

**验收（fork73 装机）**：`#话题#` / `@昵称` 点击恢复正常跳转 ✓；文案仍是粗体、颜色 / 行距 / "展开" 均无变化 ✓。

**附带修正一个旧认知**：`YYLabel` 是 **`UIView` 子类**（不是 `UILabel`），所以
`DYYYUtils applyBoldFontRecursivelyInView:`（只认 `UILabel` / `UITextView`）**根本碰不到文案标签** ——
真正让文案变粗的只有 `dyyy_directBoldFont` 这一条路，这也是当初必须单独写它的原因。

> 另：`AWEPlayInteractionDescriptionScrollView` 里那句 `isKindOfClass:DescriptionLabel` **保留未动**：
> 它的真假取决于这两个类的真实继承关系（`AwemeHeaders.h` 里的声明是猜的，见上条修正），
> 两种情况都无害；要清得先拿真机 dump 类层级，不划算。

## 二十二、「本地气泡装扮」：把商店里的气泡套到自己发的气泡上（fork74）

**需求**：气泡商店里点开某个气泡 → 详情半屏面板 → 在官方「兑换并装扮」旁加一个「本地装扮」，
把这张皮**只在本地**套到自己发出去的聊天气泡上（不花火星、不改服务端状态、对方看不到）。

### 抖音的实现机制（8 轮真机探针换来）

| 事实 | 证据 |
|---|---|
| 气泡按「**每条消息**自带的 bubbleID」渲染 | `AWEIMMessageBubbleBackgroundComponent - setMsgBubbleID:` 每条消息调一次 |
| 资源缓存键 = `<bubbleID>_self`（我发的）/ `<bubbleID>_peer`（对方） | `localImageForKey:"7688…_self" → <BDImage {66,54}>` |
| 图 = 66×54 的九宫格 `BDImage`；布局 = flex dict（`flex_setting` 四元组 + `height` + `text_setting`） | `getCacheFlexSettingWithBubbleID:` 的返回 |
| **文字颜色在 `getCacheOtherSettingWithBubbleID:` 的 `text_color` 字段，且用裸 id（无后缀）读** | `other = { text_color = "#FFF2CB"; … }`；渲染期间 other 族只被**裸 id** 调用 |
| 未拥有的气泡，资源也能按 id 拉下来 | 调一次 `AWEIMUserBubbleComponent - tryRequestBubbleImageWithBubbleID:` 后 `<新id>_self` 的图就有了 |
| 面板是 Lynx 页（`AnnieX.AnnieXNavigationController` + `BDXPopupViewController`），条目数据在 JS 运行时里，原生对象图上拿不到 | KVC 探测只有 `context` / `globalProps` / `params(accessKey)` |
| 面板里那个气泡的 id / 名字可从**桥接上报事件**精确取 | `BDXBridgeReportAppLogMethod` 的 params：`eventName="bubble_redemption_page_show"` + `bubble_id` + `bubble_name` |

### 实现（fork74）

- `DYYYChatBubbleDress.h/.m`：状态（本地气泡 id/名字持久化、面板事件缓冲、改写判定）+ 面板按钮；
- `DYYYChatBubbleDressHook.xm`：4 类 Hook —— `AWEIMUserBubbleUtility`（记住我当前气泡 id）、
  `AWEIMUserBubbleCacheManager`（9 个读取方法做键改写）、`BDXBridgeReportAppLogMethod`（抓面板条目）、
  `UIViewController`（按钮显隐）；
- 换皮 = 键改写：命中「我当前气泡 id」的**裸 id 或 `<id>_self`** → 换成本地 id（带降级链）；
  **`_peer` 一律不动**（对方的气泡不换）；
- 按钮只在气泡详情面板出现，位置**挤进官方「兑换并装扮」右侧空位**（按"整宽 + 高 26~64 + 下半屏 + 红粉底色"
  在视图树里找官方按钮；找不到就退回右下角固定位）。

### 可复用的坑（都付过学费）

- ⚠️ **绝不要对 Lynx / BDX 对象做 `object_getIvar`** —— 那类对象里有失效指针，读下去必闪退（第三轮实测）。
  只用 KVC（异常可捕获）或纯 Foundation 容器遍历；
- **主线程扫 20 万个类 = 启动卡好几秒**：`objc_getClassList` + 逐类 `class_copyMethodList` 必须丢后台；
- **改写要看"键的形状"**：同一份设置抖音会用两种键读（`<id>_self` 与**裸 id**），只按后缀匹配会漏掉颜色那条路
  —— 第七轮"文字颜色还是旧的"就是这么来的；
- **降级链里塞 `_peer` 会误伤对方气泡**：`<本地id>_peer` 正好被对方气泡的读取命中（第七轮实测 58 次）。
  只改我发的，就只认 `_self` 与裸 id；
- **Theos 命名坑**：`X.xm` 经 Logos 会生成 `X.m` —— **不能同时存在 `X.xm` 与手写的 `X.m`**（互相覆盖，
  表现为链接期 `_OBJC_CLASS_$_X` undefined）。手写类与 Hook 文件必须不同名（本项目用 `…Hook.xm`）；
- 抓取优先**结构化字段**而不是正则碰运气：`BDXBridgeReportAppLogMethod` 的参数模型可以直接 KVC 取
  `eventName` / `params`，比在 `description` 里找数字可靠得多（第五轮就是被"日志 id"骗了）。

### 边界与安全

- 只改**本机渲染**：官方侧记录你拥有的仍是原来那个气泡，对方看到的也还是官方皮肤；
- 抖音改版后若类名/字段变了，任一环读不到即**原样返回官方气泡**（安全降级，不会出现空气泡）；
- 设置页有总开关「本地气泡装扮」（关掉立即恢复官方气泡），面板按钮再点一下 = 清除本地装扮。

### 面板按钮的最终形态（fork79~fork82 打磨）

- 与官方「兑换并装扮」**并排**：官方那颗压窄到左半边（里面的居中文字同步左移，目标位置与 Lynx 自己居中的结果一致，不会互相打架），
  本地装扮占右半边，同高同圆角；描边/文字色取**官方按钮自己的底色**（官方绿就绿、红就红）；
- 按钮文字随状态走：面板里这个气泡**就是**当前装扮的那个 → 显示「恢复装扮」（淡色填充），否则显示「本地装扮」；
- 只在真面板（`BDXPopup`）且找到官方按钮容器时出现 —— **不做悬浮兜底**（宁可没有按钮，也不漂在面板外面）；
- Lynx 异步渲染 → 面板打开后**立刻 + 每 0.06 秒**密集重试约 1.5 秒（找到容器后每拍只做一次 frame 比对），
  之后 2.0/2.6/3.4 秒慢速兜底，让用户几乎看不到"官方按钮先单独出现、再分成两颗"的中间态。

### 另两条踩过的坑（fork78→fork82）

- ⚠️ **布局改写必须幂等**：一开始拿"当前宽度"当基准去算，重试链每跑一轮就把官方按钮再压窄一圈，
  最后收敛到钳位值（官方 120 + 本地 96，"两颗短条挤在左边"）。正解 = **第一次记下原始几何，之后都从原始值算**，
  写之前再比对（差值 < 0.5pt 就不写）；
- ⚠️ **记住的容器要校验归属**：上一个面板的视图可能还被短暂持有，若盲目复用会去压窄上一个面板的按钮 ——
  必须用 `[container isDescendantOfView:controller.view]` 确认它属于当前面板；
- 「我当前的官方气泡 id」**不要只依赖 `AWEIMUserBubbleUtility currentUserBubbleID`**（一次启动只调一次）：
  从 `<某id>_self` 的键里推断并持久化，重启后直接进聊天也能立刻生效（且要排除"本地气泡 id"与"面板里正在看的 id"）。



