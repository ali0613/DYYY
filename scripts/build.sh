#!/usr/bin/env bash
#
# DYYY 分支构建（在 WSL Ubuntu 内以 builder 用户执行）
#   bash /mnt/d/xiazai/dsh/dyyy/scripts/build.sh [roothide|rootless|rootful]
#
# 关键：源码复制到 WSL 原生文件系统再构建。
# /mnt/d 是 drvfs，符号链接与文件权限语义不完整，theos 会踩坑（且慢 10 倍以上）。
#
set -euo pipefail

SCHEME="${1:-roothide}"
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

echo "==> 编译（SCHEME=$SCHEME）"
make package SCHEME="$SCHEME"

DEB="$(ls -t "$WORK"/packages/*.deb | head -1)"

echo
echo "==> 包信息"
dpkg-deb -f "$DEB" Package Name Version Architecture Depends Conflicts Replaces
echo
echo "==> 包内结构"
dpkg-deb -c "$DEB"

echo
echo "==> 产物哈希"
sha256sum "$DEB"

mkdir -p "$SRC/packages"
cp "$DEB" "$SRC/packages/"
echo
echo "==> 已回传到 $SRC/packages/"
ls -lh "$SRC/packages/"*.deb
