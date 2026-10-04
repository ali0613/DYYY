#!/usr/bin/env bash
#
# DYYY 分支产物校验（在 WSL Ubuntu 内以 builder 用户执行）
#   bash /mnt/d/xiazai/dsh/dyyy/scripts/verify.sh [deb路径]
#
# 校验项：包元信息 / dylib 架构 / 垫片符号是否落地 / 抖音 hook 符号是否在位
#        / 有无历史自研产物残留 / %ctor 段是否生成 / 过滤器 plist
#
set -euo pipefail

POOL="${1:-}"
if [ -z "$POOL" ]; then
    if ls "$HOME/dyyy-build/packages/"*.deb >/dev/null 2>&1; then
        POOL="$(ls -t "$HOME/dyyy-build/packages/"*.deb | head -1)"
    else
        POOL="$(ls -t /mnt/d/xiazai/dsh/dyyy/packages/*.deb | head -1)"
    fi
fi

THEOS="${THEOS:-$HOME/theos}"
TOOLBIN="$THEOS/toolchain/linux/iphone/bin"
NM="$TOOLBIN/llvm-nm"
OUT=/tmp/dyyy-verify

echo "==> 校验对象：$POOL"
rm -rf "$OUT"; mkdir -p "$OUT"
dpkg-deb -x "$POOL" "$OUT"

DYLIB="$(find "$OUT" -name '*.dylib' | head -1)"
PLIST="$(find "$OUT" -name '*.plist' | head -1)"

echo
echo "==> 包元信息"
dpkg-deb -f "$POOL" Package Name Version Architecture Depends Conflicts Replaces

echo
echo "==> 载荷"
ls -l "$DYLIB" "$PLIST"
echo "过滤器：$(cat "$PLIST")"

echo
echo "==> 架构"
"$TOOLBIN/llvm-lipo" -info "$DYLIB" 2>/dev/null || file "$DYLIB"

echo
echo "==> 垫片符号 __isOSVersionAtLeast（应为已定义的 T/t，不是 U）"
"$NM" "$DYLIB" | grep -i 'isOSVersionAtLeast' || echo "!! 缺失：@available 会链接失败，说明垫片没编进去"

echo
echo "==> 仍属未定义的符号（不应出现 isOSVersionAtLeast / UIImageDynamicRangeStandard）"
"$NM" -u "$DYLIB" | grep -Ei 'isOSVersionAtLeast|UIImageDynamicRange' && exit 1 || echo "OK：无残留未定义符号"

echo
echo "==> 抖音 hook 符号（%ctor 与 DYYY 类）"
"$NM" "$DYLIB" | grep -c '_OBJC_CLASS_\$_DYYY' | sed 's/^/DYYY 类数量: /'
"$NM" -s __DATA __mod_init_func "$DYLIB" >/dev/null 2>&1 && echo "mod_init 段: 存在" || echo "mod_init 段: 未检出"

echo
echo "==> 历史自研产物残留检查（应为 0）"
COUNT="$("$NM" "$DYLIB" | grep -c 'DYUI' || true)"
echo "DYUI 相关符号: $COUNT"
[ "$COUNT" -eq 0 ] || exit 1

echo
echo "==> SHA256"
sha256sum "$POOL"
