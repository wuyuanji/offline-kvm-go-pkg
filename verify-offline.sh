#!/usr/bin/env bash
# =============================================================================
# verify-offline.sh
# 对已完成的离线安装做完整功能验证
# =============================================================================
# 用法:
#   bash verify-offline.sh
# =============================================================================

set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "${result}" = "0" ]; then
        echo "[PASS] ${desc}"
        PASS=$((PASS+1))
    else
        echo "[FAIL] ${desc}"
        FAIL=$((FAIL+1))
    fi
}

echo "=============================================="
echo "离线安装完整性验证"
echo "=============================================="

# 1. 核心二进制存在性
check "qemu-system-x86_64"   "$(command -v qemu-system-x86_64 >/dev/null 2>&1; echo $?)"
check "qemu-img"             "$(command -v qemu-img >/dev/null 2>&1; echo $?)"
check "virsh"                "$(command -v virsh >/dev/null 2>&1; echo $?)"
check "brctl (bridge-utils)" "$(command -v brctl >/dev/null 2>&1; echo $?)"
check "gcc"                  "$(command -v gcc >/dev/null 2>&1; echo $?)"
check "git"                  "$(command -v git >/dev/null 2>&1; echo $?)"
check "make"                 "$(command -v make >/dev/null 2>&1; echo $?)"
check "go"                   "$(bash -lc 'command -v go' >/dev/null 2>&1; echo $?)"

# 2. libvirt 头文件
check "libvirt-dev 头文件 (/usr/include/libvirt/libvirt.h)" "$(test -f /usr/include/libvirt/libvirt.h; echo $?)"

# 3. libvirtd 服务状态
if systemctl is-active libvirtd >/dev/null 2>&1; then
    check "libvirtd 服务运行中" "0"
else
    check "libvirtd 服务运行中" "1"
fi

# 4. virsh 连接测试
check "virsh 连接 libvirt" "$(virsh list --all >/dev/null 2>&1; echo $?)"

# 5. qemu-img 功能测试
qemu-img create -f qcow2 /tmp/.verify.qcow2 64M >/dev/null 2>&1
check "qemu-img 创建磁盘镜像" "$?"
qemu-img info /tmp/.verify.qcow2 >/dev/null 2>&1
check "qemu-img 查询磁盘镜像" "$?"
rm -f /tmp/.verify.qcow2

# 6. 版本汇总
echo ""
echo "--- 版本信息 ---"
qemu-system-x86_64 --version 2>/dev/null | head -1
virsh --version 2>/dev/null
gcc --version 2>/dev/null | head -1
git --version 2>/dev/null
make --version 2>/dev/null | head -1
bash -lc 'go version' 2>/dev/null

echo ""
echo "=============================================="
echo "验证结果: PASS=${PASS}  FAIL=${FAIL}"
if [ "${FAIL}" -eq 0 ]; then
    echo "✅ 全部验证通过"
    exit 0
else
    echo "❌ 存在 ${FAIL} 项失败"
    exit 1
fi
