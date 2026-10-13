#!/usr/bin/env bash
# =============================================================================
# install-offline.sh
# 在目标机器（离线安装端）上安装 KVM/libvirt/Go 离线包
# =============================================================================
# 用法:
#   bash install-offline.sh [离线包路径]
#
# 说明:
#   1. 默认读取当前目录或 /root 下的 offline-kvm-go-pkgs.tar.gz
#   2. 全程离线安装（不依赖网络 apt 源）
#   3. 使用 dpkg -i 批量安装，自动处理依赖顺序
# =============================================================================

set -euo pipefail

TARBALL="${1:-offline-kvm-go-pkgs.tar.gz}"
INSTALL_ROOT="/opt/offline-install"

# 查找离线包（支持当前目录 / /root）
if [ ! -f "${TARBALL}" ]; then
    if [ -f "/root/${TARBALL}" ]; then
        TARBALL="/root/${TARBALL}"
    else
        echo "错误: 找不到离线包 ${TARBALL}"
        echo "用法: bash install-offline.sh [离线包路径]"
        exit 1
    fi
fi

echo "=============================================="
echo "[1/6] 解压离线包"
echo "=============================================="
rm -rf "${INSTALL_ROOT}"
mkdir -p "${INSTALL_ROOT}"
cd "${INSTALL_ROOT}"
TARBALL_ABS="$(cd "$(dirname "${TARBALL}")" && pwd)/$(basename "${TARBALL}")"
tar xzf "${TARBALL_ABS}"
ls -la

echo "=============================================="
echo "[2/6] 校验 SHA256 完整性"
echo "=============================================="
cd "${INSTALL_ROOT}/debs"
sha256sum -c "${INSTALL_ROOT}/SHA256SUMS"
echo "--- 校验通过 ---"

# go 包单独校验（它在上级目录）
cd "${INSTALL_ROOT}"
sha256sum "go1.24.5.linux-amd64.tar.gz" | grep -qF "$(grep 'go1.24.5' SHA256SUMS | awk '{print $1}')" \
    && echo "Go 包校验通过" \
    || { echo "Go 包校验失败"; exit 1; }

echo "=============================================="
echo "[3/6] 备份并禁用网络 apt 源（保证纯离线）"
echo "=============================================="
cp /etc/apt/sources.list "${INSTALL_ROOT}/sources.list.bak" 2>/dev/null || true
sed -i 's|^deb http|#deb http|; s|^deb-src http|#deb-src http|' /etc/apt/sources.list
sed -i 's|^deb cdrom|#deb cdrom|' /etc/apt/sources.list

echo "--- 确认网络源已禁用 ---"
if grep -E '^deb (http|cdrom)' /etc/apt/sources.list; then
    echo "警告: 仍有活跃网络源，请手动检查"
else
    echo "已进入纯离线模式"
fi

echo "=============================================="
echo "[4/6] 离线安装所有 .deb 包"
echo "=============================================="
cd "${INSTALL_ROOT}/debs"
dpkg -i ./*.deb

echo "=============================================="
echo "[5/6] 安装 Go 1.24.5"
echo "=============================================="
cd "${INSTALL_ROOT}"
tar -C /usr/local -xzf "go1.24.5.linux-amd64.tar.gz"

# 配置环境变量
cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/root/go
export GOPROXY=https://proxy.golang.org,direct
EOF
chmod +x /etc/profile.d/go.sh

echo "=============================================="
echo "[6/6] 安装完成，开始验证"
echo "=============================================="
echo "--- 核心工具 ---"
for c in qemu-system-x86_64 qemu-img virsh bridge gcc g++ git make; do
    if command -v "$c" >/dev/null 2>&1; then
        echo "[OK] $c -> $(command -v "$c")"
    else
        echo "[--] $c (未安装/未在需求内)"
    fi
done

echo "--- 版本 ---"
qemu-system-x86_64 --version 2>/dev/null | head -1
qemu-img --version 2>/dev/null | head -1
virsh --version 2>/dev/null
gcc --version 2>/dev/null | head -1
git --version 2>/dev/null
make --version 2>/dev/null | head -1
bash -lc 'go version' 2>/dev/null || echo "go 需重新登录后生效"

echo "--- libvirt-dev 头文件 ---"
test -f /usr/include/libvirt/libvirt.h && echo "[OK] libvirt.h 存在" || echo "[FAIL] 缺少 libvirt.h"

echo "--- libvirtd 服务 ---"
systemctl is-active libvirtd 2>/dev/null || echo "(服务未自动启动，可手动 systemctl start libvirtd)"

echo ""
echo "=============================================="
echo "离线安装完成！"
echo "可运行 verify-offline.sh 做完整功能验证"
echo "=============================================="
