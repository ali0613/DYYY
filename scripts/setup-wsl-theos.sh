#!/usr/bin/env bash
#
# DYYY 分支构建环境初始化（在 WSL Ubuntu 内以 root 执行）
#   bash /mnt/d/xiazai/dsh/dyyy/scripts/setup-wsl-theos.sh
#
# 关键事实（已实测确认）：
#   1. theos 拒绝以 root 安装/运行 → 必须用普通用户（builder）
#   2. roothide 越狱需要 roothide/theos（官方 fork，与主线 100% 兼容），
#      官方 theos 的 vendor/mod/ 只有 rootless，没有 roothide
#   3. Linux 工具链：L1ghtmann/llvm-project 的 iOSToolchain-<arch>.tar.xz
#      （clang 11.1.0，不带 compiler-rt —— 所以仓库里有 compat/ 垫片）
#   4. SDK：$THEOS/bin/install-sdk latest（内部拉 theos/sdks 的 release）
#
set -euo pipefail

BUILDER="${BUILDER:-builder}"
USE_CN_MIRROR="${USE_CN_MIRROR:-1}"
ARCH="$(uname -m)"
THEOS_DIR="/home/$BUILDER/theos"
THEOS_REPO="${THEOS_REPO:-https://github.com/roothide/theos.git}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请以 root 执行：wsl -d Ubuntu22 -u root -- bash \$0"

# ---------------------------------------------------------------- 1. apt 源
log "[1/6] 配置 apt 源"
if [ "$USE_CN_MIRROR" = "1" ]; then
    if [ -f /etc/apt/sources.list ] && [ ! -f /etc/apt/sources.list.dyyy-bak ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.dyyy-bak
        cat > /etc/apt/sources.list <<'EOF'
deb https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF
        echo "    已切换到 aliyun 镜像"
    else
        echo "    已是镜像源或已备份，跳过"
    fi
fi

# ---------------------------------------------------------------- 2. 依赖
log "[2/6] 安装系统依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl wget git make perl zip unzip rsync xz-utils \
    build-essential fakeroot dpkg-dev sudo file \
    libxml2 libtinfo5 libssl-dev libz3-dev python3 \
    && echo "    完成"

# ---------------------------------------------------------------- 3. 用户
log "[3/6] 构建用户 $BUILDER"
id "$BUILDER" >/dev/null 2>&1 || { useradd -m -s /bin/bash "$BUILDER"; echo "    已创建"; }
echo "$BUILDER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$BUILDER"
chmod 440 "/etc/sudoers.d/$BUILDER"

# ---------------------------------------------------------------- 4. theos
log "[4/6] 安装 theos（roothide fork）"
su - "$BUILDER" -c "
set -e
if [ ! -d \"\$HOME/theos/.git\" ]; then
    git clone --recursive --depth 1 $THEOS_REPO \"\$HOME/theos\"
else
    echo '    theos 已存在'
fi
grep -q 'THEOS=' \"\$HOME/.bashrc\" 2>/dev/null || {
    printf '\nexport THEOS=\$HOME/theos\nexport PATH=\"\$THEOS/bin:\$PATH\"\n' >> \"\$HOME/.bashrc\"
}
"

# ---------------------------------------------------------------- 5. 工具链
log "[5/6] iOS 工具链（$ARCH）"
if [ -x "$THEOS_DIR/toolchain/linux/iphone/bin/clang" ]; then
    echo "    已存在"
else
    su - "$BUILDER" -c "
    set -e
    mkdir -p \$HOME/theos/toolchain
    curl -sSL --max-time 1800 \
        https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$ARCH.tar.xz \
        | tar -xJ -C \$HOME/theos/toolchain/
    "
fi
[ -x "$THEOS_DIR/toolchain/linux/iphone/bin/clang" ] || die "工具链缺失"
"$THEOS_DIR/toolchain/linux/iphone/bin/clang" --version 2>/dev/null | head -1

# ---------------------------------------------------------------- 6. SDK
log "[6/6] iOS SDK"
if ls "$THEOS_DIR"/sdks/*.sdk >/dev/null 2>&1; then
    echo "    已存在"
else
    su - "$BUILDER" -c '
    set -e
    export THEOS="$HOME/theos"
    export PATH="$THEOS/bin:$PATH"
    if ! install-sdk latest; then
        echo "    install-sdk 失败，回退 git clone theos/sdks"
        rm -rf "$THEOS/sdks"
        git clone --depth 1 https://github.com/theos/sdks.git "$THEOS/sdks"
    fi
    '
fi
echo "    SDK：$(ls "$THEOS_DIR/sdks" 2>/dev/null | tr '\n' ' ')"

# ---------------------------------------------------------------- 校验
log "校验"
echo "THEOS = $THEOS_DIR"
echo -n "scheme 模块: "
ls "$THEOS_DIR/vendor/mod/" 2>/dev/null | tr '\n' ' '
echo
echo -n "roothide 支持: "
[ -d "$THEOS_DIR/vendor/mod/roothide" ] && echo "有" || echo "缺失"
echo -n "ldid: "
ls "$THEOS_DIR/toolchain/linux/iphone/bin/" | grep -i '^ldid' | tr '\n' ' '
echo
echo
echo "下一步构建："
echo "  wsl -d Ubuntu22 -- bash /mnt/d/xiazai/dsh/dyyy/scripts/build.sh roothide"
