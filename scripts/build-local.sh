#!/usr/bin/env bash
#
# DYYY 本地出包（不需要 CI）
#   用法（在 WSL 内）: bash /mnt/d/xiazai/dsh/dyyy/scripts/build-local.sh [arm64|both]
#
# 为什么默认只打 arm64：
#   Linux 侧 clang 编出的 arm64e 目标文件与 iOS 的 arm64e ABI 不兼容
#   （ld: "built with an incompatible arm64e ABI compiler"），装到设备上会崩。
#   而抖音是 App Store 应用 = 纯 arm64，插件只要 arm64 就能注入，
#   所以「纯 arm64 包」既避开这个 ABI 问题，又不影响使用。
#
set -euo pipefail

ARCH_MODE="${1:-arm64}"
SRC="/mnt/d/xiazai/dsh/dyyy"
WORK="$HOME/dyyy-build"

export THEOS="${THEOS:-$HOME/theos}"
export PATH="$THEOS/bin:$PATH"

command -v make >/dev/null || { echo "缺少 make"; exit 1; }
[ -d "$THEOS" ] || { echo "THEOS 不存在: $THEOS"; exit 1; }

echo "==> 同步源码 -> $WORK"
mkdir -p "$WORK"
rsync -a --delete \
      --exclude '.theos' --exclude 'packages' --exclude '.git' \
      "$SRC/" "$WORK/"

cd "$WORK"
echo "==> 清理旧产物"
make clean >/dev/null 2>&1 || true

ARCHS_ARG=""
[ "$ARCH_MODE" = "both" ] || ARCHS_ARG="ARCHS=arm64"

echo "==> 编译（SCHEME=roothide, ARCHS=${ARCH_MODE}）"
make package SCHEME=roothide $ARCHS_ARG

DEB="$(ls -t "$WORK"/packages/*.deb | head -1)"

echo
echo "==> 包信息"
dpkg-deb -f "$DEB" Package Version Architecture
echo
echo "==> 架构自检（期望：只有 arm64）"
TMPD="$(mktemp -d)"
dpkg-deb -x "$DEB" "$TMPD"
DY="$(find "$TMPD" -name 'DYYY.dylib' | head -1)"
if [ -n "$DY" ]; then
    file "$DY"
fi
rm -rf "$TMPD"

mkdir -p "$SRC/packages"
cp "$DEB" "$SRC/packages/"
echo
echo "==> 已放到 $SRC/packages/"
ls -lh "$SRC/packages/"*.deb | tail -3

# 可选第二步参数 install：编译完直接推送到设备安装并重启抖音
#   用法: bash scripts/build-local.sh arm64 install
#   前提: 已把 packages/wsl_key.pub 追加到设备的 /var/root/.ssh/authorized_keys（免密）
INSTALL_MODE="${2:-}"
if [ "$INSTALL_MODE" = "install" ]; then
    DEVICE_IP="${DYYY_DEVICE_IP:-192.168.1.19}"
    echo
    echo "==> 推送到设备 $DEVICE_IP 并安装"
    scp -O -o StrictHostKeyChecking=no "$DEB" "root@$DEVICE_IP:/tmp/dyyy-local.deb"
    ssh -o StrictHostKeyChecking=no "root@$DEVICE_IP" \
        "dpkg -i --force-overwrite /tmp/dyyy-local.deb >/dev/null 2>&1 && rm -f /tmp/dyyy-local.deb && killall -9 Aweme >/dev/null 2>&1; echo '安装完成，抖音已重启'"
fi
