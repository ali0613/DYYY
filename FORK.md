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

**验收结果：位置没有任何变化** —— 这符合预期，而且能用那份日志直接算清楚原因：

`applyLiveCardScaleToStack:` 里是 `CGAffineTransformConcat(平移, 缩放)`，**平移先作用、随后整体被缩放**，
所以最终 `tx' = tx × 0.8 = −40.4 × 0.8 = −32.32`、`ty' = ty × 0.8 = −92.6 × 0.8 = −74.08`
（`tx`/`ty` 由 `bounds = 404×926`、`base = identity`、`shiftUp = 0` 算出）—— 与日志里那串
`[0.8, 0, 0, 0.8, −32.32, −74.08]` **完全吻合**。

结论：**真正最后生效的一直是我们自己的写入**；`-20` 只在布局帧里短暂赢过一次，随即被
`setAlpha:` / `didMoveToWindow` 那几条入口盖掉。所以删掉它**画面不动**，但"中途把缩放抹掉一帧"的抖动来源消失了。

