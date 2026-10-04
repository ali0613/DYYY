#
#  DYYY —— 个人维护分支
#
#  上游：https://github.com/Wtrwx/DYYY （2.2-9 线）
#  基线：commit 6bdc7c3 / tag DYYY_2.2-9#1687
#  原仓库：https://github.com/huami1314/DYYY （2.2-8 线，另有 remote: huami）
#
#  本文件属于「构建适配层」（上游同名文件已被替换），改动原因见 FORK.md：
#    1. 追加 roothide 架构对齐（上游 control 写死 iphoneos-arm，roothide 包会被标错）；
#    2. DYYY_FILES 追加 compat/osversion-compat.m（本机 clang 11 缺 compiler-rt 符号）；
#    3. DYYY_CFLAGS 追加 -include compat/sdk17-compat.h（iPhoneOS16.5 SDK 缺 iOS 17 声明）。
#  源码文件保持与上游逐字节一致。
#
#  打包方案（默认 roothide）：
#      make package                   # roothide（本机设备）
#      make package SCHEME=rootless   # rootless（/var/jb）
#      make package SCHEME=rootful    # 传统越狱
#
#  设备安装：make package INSTALL=1 THEOS_DEVICE_IP=192.168.x.x
#  本地私有配置写 Makefile.local，不要改本文件。
#

-include Makefile.local

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

SCHEME ?= roothide

# 根据参数选择打包方案
ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

# 各越狱形态要求的包架构标记。
# 注意：CI（.github/workflows/build-deb.yml）不走 SCHEME 参数，而是直接
# `make package THEOS_PACKAGE_SCHEME=rootless`，这时以命令行为准；否则三种 scheme
# 会被统一标成 roothide 的架构，rootless 包在 Sileo 里装不上。
ifeq ($(origin THEOS_PACKAGE_SCHEME),command line)
    ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
        DYYY_PACKAGE_ARCH := iphoneos-arm64
    else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
        DYYY_PACKAGE_ARCH := iphoneos-arm64e
    else
        DYYY_PACKAGE_ARCH := iphoneos-arm
    endif
else ifeq ($(SCHEME),roothide)
    DYYY_PACKAGE_ARCH := iphoneos-arm64e
else ifeq ($(SCHEME),rootless)
    DYYY_PACKAGE_ARCH := iphoneos-arm64
else
    DYYY_PACKAGE_ARCH := iphoneos-arm
endif

# theos 的 package/deb.mk:26 会从项目 control 文件回读 Architecture，优先级高于
# scheme 模块设的值；不在这里对齐，roothide 包会被标成 iphoneos-arm（Sileo 装不上）。
# sed 用 -i.bak 形式：GNU sed 与 macOS 的 BSD sed 都认（BSD sed 不认裸 -i 后跟脚本），
# 否则 CI 的 macOS runner 上会静默跳过对齐、三个 scheme 全被标成同一个架构。
_DYYY_CONTROL_SYNC := $(shell sed -i.bak 's/^Architecture:.*/Architecture: $(DYYY_PACKAGE_ARCH)/' $(CURDIR)/control >/dev/null 2>&1; rm -f $(CURDIR)/control.bak; echo synced)

# GitHub Actions 等无人值守环境只出包
ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYYY

# 名单与上游 Makefile 保持一致，仅在末尾追加工具链垫片。
DYYY_FILES = DYYY.xm DYYYFloatClearButton.xm DYYYFloatSpeedButton.m DYYYSettings.xm DYYYABTestHook.xm DYYYLongPressPanel.xm DYYYSettingsHelper.m DYYYImagePickerDelegate.m DYYYBackupPickerDelegate.m DYYYSettingViewController.m DYYYBottomAlertView.m DYYYCustomInputView.m DYYYOptionsSelectionView.m DYYYIconOptionsDialogView.m DYYYAboutDialogView.m DYYYKeywordListView.m DYYYFilterSettingsView.m DYYYConfirmCloseView.m DYYYToast.m DYYYManager.m DYYYUtils.m CityManager.m AWMSafeDispatchTimer.m compat/osversion-compat.m
DYYY_CFLAGS = -fobjc-arc -w -include $(CURDIR)/compat/sdk17-compat.h
DYYY_LDFLAGS = -weak_framework AVFAudio
DYYY_FRAMEWORKS = CoreAudio
CXXFLAGS += -std=c++11
CCFLAGS += -std=c++11
DYYY_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS = 0
export ERROR_ON_WARNINGS = 0
export LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

# 设备安装（可选）：make package INSTALL=1 THEOS_DEVICE_IP=192.168.x.x
THEOS_DEVICE_PORT ?= 22

# 清理 packages 目录
clean::
	@echo "==> 清理 packages / .theos"
	@rm -rf .theos packages

after-package::
	@echo "==> 打包完成，产物在 packages/"
	@if [ "$(GITHUB_ACTIONS)" != "true" ] && [ "$(INSTALL)" = "1" ]; then \
		DEB=$$(ls -t packages/*.deb | head -1); \
		echo "==> 安装 $$DEB 到 $(THEOS_DEVICE_IP)"; \
		scp "$$DEB" root@$(THEOS_DEVICE_IP):/tmp/dyyy.deb; \
		ssh root@$(THEOS_DEVICE_IP) "dpkg -i --force-overwrite /tmp/dyyy.deb && rm -f /tmp/dyyy.deb"; \
	else \
		echo "==> 跳过设备安装（INSTALL != 1）"; \
	fi
