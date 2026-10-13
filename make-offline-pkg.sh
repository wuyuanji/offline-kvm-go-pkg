#!/usr/bin/env bash
# =============================================================================
# make-offline-pkg.sh
# 在联网机器（制作端）上制作 Debian 11 (bullseye) KVM/libvirt/Go 离线安装包
# =============================================================================
# 用法:
#   bash make-offline-pkg.sh
#
# 说明:
#   1. 本脚本在 10.12.5.216 上执行（密码 root/acoinfo）
#   2. 下载 qemu-kvm、libvirt、bridge-utils 及开发依赖、Go 1.24.5 二进制包
#   3. 生成离线包 offline-kvm-go-pkgs.tar.gz
#   4. 关键点: 只使用 bullseye main 源（security/updates 源已 EOL 会 404）
# =============================================================================

set -euo pipefail

WORK_DIR="/root/offline_pkg"
DEBS_DIR="${WORK_DIR}/debs"
GO_VERSION="1.24.5"
GO_FILE="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_FILE}"
OUT_TARBALL="offline-kvm-go-pkgs.tar.gz"

# 需要安装的目标包（含开发依赖）
PKGS=(
    qemu-kvm
    qemu-utils
    libvirt-daemon
    libvirt-daemon-system
    libvirt-clients
    bridge-utils
    libvirt-dev
    gcc
    git
    make
)

echo "=============================================="
echo "[1/6] 备份并配置 apt 源（仅使用 bullseye main）"
echo "=============================================="
mkdir -p "${WORK_DIR}"
cp /etc/apt/sources.list "${WORK_DIR}/sources.list.bak"

# 注释掉 security / updates 源（bullseye 已 EOL，镜像文件会 404）
sed -i 's|^deb http://mirrors.aliyun.com/debian-security/|#deb http://mirrors.aliyun.com/debian-security/|' /etc/apt/sources.list
sed -i 's|^deb http://mirrors.aliyun.com/debian/ bullseye-updates|#deb http://mirrors.aliyun.com/debian/ bullseye-updates|' /etc/apt/sources.list
sed -i 's|^deb cdrom|#deb cdrom|' /etc/apt/sources.list

echo "--- 当前有效源 ---"
grep -E '^deb ' /etc/apt/sources.list || true

echo "=============================================="
echo "[2/6] 更新 apt 索引"
echo "=============================================="
apt-get update

echo "=============================================="
echo "[3/6] 下载所有软件包及依赖（--download-only）"
echo "=============================================="
rm -rf "${DEBS_DIR}"
mkdir -p "${DEBS_DIR}"
apt-get install --download-only -y \
    -o Dir::Cache::archives="${DEBS_DIR}" \
    "${PKGS[@]}"

echo "--- 已下载 deb 数量 ---"
ls "${DEBS_DIR}"/*.deb | wc -l

echo "=============================================="
echo "[4/6] 下载 Go ${GO_VERSION} 二进制包"
echo "=============================================="
cd "${WORK_DIR}"
wget -q "${GO_URL}" -O "${GO_FILE}"
ls -lh "${GO_FILE}"

echo "=============================================="
echo "[5/6] 生成包清单与 SHA256 校验"
echo "=============================================="
cd "${WORK_DIR}"
ls "${DEBS_DIR}"/*.deb | sort > pkg-list.txt
cd "${DEBS_DIR}"
sha256sum *.deb > "${WORK_DIR}/SHA256SUMS"
cd "${WORK_DIR}"
sha256sum "${GO_FILE}" >> SHA256SUMS
echo "--- 校验项数量 ---"
wc -l < SHA256SUMS

echo "=============================================="
echo "[6/6] 打包离线安装包"
echo "=============================================="
cd "${WORK_DIR}"
tar czf "${OUT_TARBALL}" \
    debs/ \
    "${GO_FILE}" \
    pkg-list.txt \
    SHA256SUMS

echo "--- 离线包信息 ---"
ls -lh "${OUT_TARBALL}"
md5sum "${OUT_TARBALL}"

echo ""
echo "=============================================="
echo "制作完成: ${WORK_DIR}/${OUT_TARBALL}"
echo "请通过 scp 传输到目标机器后执行 install-offline.sh"
echo "=============================================="
