#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

DEFCONFIG="arch/arm64/configs/vendor/sweet_defconfig"

echo "=== Applying Droidspaces, Performance & Container kernel options in sweet_defconfig..."

# 1. Enable SYSVIPC & POSIX_MQUEUE (IPC dependencies)
sed -i 's/# CONFIG_SYSVIPC is not set/CONFIG_SYSVIPC=y\nCONFIG_SYSVIPC_SYSCTL=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_POSIX_MQUEUE is not set/CONFIG_POSIX_MQUEUE=y/' "$DEFCONFIG"

# 2. Enable CPU and Process limits (CFS_BANDWIDTH, CGROUP_PIDS, CGROUP_DEVICE)
sed -i 's/# CONFIG_CFS_BANDWIDTH is not set/CONFIG_CFS_BANDWIDTH=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_CGROUP_PIDS is not set/CONFIG_CGROUP_PIDS=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_CGROUP_DEVICE is not set/CONFIG_CGROUP_DEVICE=y/' "$DEFCONFIG"

# 3. Enable Namespaces (PID, IPC, USER)
sed -i 's/# CONFIG_USER_NS is not set/CONFIG_USER_NS=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_PID_NS is not set/CONFIG_PID_NS=y/' "$DEFCONFIG"
grep -q "CONFIG_IPC_NS=y" "$DEFCONFIG" || sed -i '/CONFIG_UTS_NS=y/a CONFIG_IPC_NS=y' "$DEFCONFIG"

# 4. Enable IPv6 NAT & Masquerade
sed -i 's/# CONFIG_NF_NAT_IPV6 is not set/CONFIG_NF_NAT_IPV6=y\nCONFIG_NF_NAT_MASQUERADE_IPV6=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_IP6_NF_NAT is not set/CONFIG_IP6_NF_NAT=y\nCONFIG_IP6_NF_TARGET_MASQUERADE=y/' "$DEFCONFIG"

# 5. Enable DEVTMPFS
sed -i 's/# CONFIG_DEVTMPFS is not set/CONFIG_DEVTMPFS=y\nCONFIG_DEVTMPFS_MOUNT=y/' "$DEFCONFIG"

# 6. Enable MACVLAN & MACVTAP
sed -i 's/# CONFIG_MACVLAN is not set/CONFIG_MACVLAN=y\nCONFIG_MACVTAP=y/' "$DEFCONFIG"

# 7. Enable ZSTD Crypto & F2FS Acceleration
sed -i 's/# CONFIG_CRYPTO_ZSTD is not set/CONFIG_CRYPTO_ZSTD=y\nCONFIG_ZSTD_COMPRESS=y\nCONFIG_ZSTD_DECOMPRESS=y\nCONFIG_F2FS_FS_ZSTD=y/' "$DEFCONFIG"

# 8. Set ZRAM default compression and recompression to ZSTD (10.74:1 density)
sed -i 's/CONFIG_ZRAM_DEFAULT_COMP_ALGORITHM="lz4"/CONFIG_ZRAM_DEFAULT_COMP_ALGORITHM="zstd"/' "$DEFCONFIG"
sed -i 's/CONFIG_ZRAM_DEFAULT_RECOMP_ALGORITHM="lzo"/CONFIG_ZRAM_DEFAULT_RECOMP_ALGORITHM="zstd"/' "$DEFCONFIG"

# 9. Enable Forensic Observability (DebugFS, Hung Task Detection, Ftrace Syscalls)
sed -i 's/# CONFIG_DEBUG_FS is not set/CONFIG_DEBUG_FS=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_DETECT_HUNG_TASK is not set/CONFIG_DETECT_HUNG_TASK=y\nCONFIG_DEFAULT_HUNG_TASK_TIMEOUT=30/' "$DEFCONFIG"
grep -q "CONFIG_FTRACE_SYSCALLS=y" "$DEFCONFIG" || sed -i '/CONFIG_FTRACE=y/a CONFIG_FTRACE_SYSCALLS=y' "$DEFCONFIG"

# 10. Enable Memory Efficiency & Bionic Safety
grep -q "CONFIG_PID_MAX_CLAMP_BIONIC=y" "$DEFCONFIG" || sed -i '/CONFIG_CROSS_MEMORY_ATTACH=y/a CONFIG_PID_MAX_CLAMP_BIONIC=y' "$DEFCONFIG"
sed -i 's/# CONFIG_KSM is not set/CONFIG_KSM=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_TRANSPARENT_HUGEPAGE is not set/CONFIG_TRANSPARENT_HUGEPAGE=y\nCONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y/' "$DEFCONFIG"

echo "=== Verifying applied configurations..."
MISSING=0
for opt in \
    "CONFIG_SYSVIPC=y" \
    "CONFIG_SYSVIPC_SYSCTL=y" \
    "CONFIG_POSIX_MQUEUE=y" \
    "CONFIG_CFS_BANDWIDTH=y" \
    "CONFIG_CGROUP_PIDS=y" \
    "CONFIG_CGROUP_DEVICE=y" \
    "CONFIG_USER_NS=y" \
    "CONFIG_PID_NS=y" \
    "CONFIG_IPC_NS=y" \
    "CONFIG_NF_NAT_IPV6=y" \
    "CONFIG_NF_NAT_MASQUERADE_IPV6=y" \
    "CONFIG_IP6_NF_NAT=y" \
    "CONFIG_IP6_NF_TARGET_MASQUERADE=y" \
    "CONFIG_DEVTMPFS=y" \
    "CONFIG_DEVTMPFS_MOUNT=y" \
    "CONFIG_MACVLAN=y" \
    "CONFIG_MACVTAP=y" \
    "CONFIG_CRYPTO_ZSTD=y" \
    "CONFIG_ZSTD_COMPRESS=y" \
    "CONFIG_ZSTD_DECOMPRESS=y" \
    "CONFIG_F2FS_FS_ZSTD=y" \
    'CONFIG_ZRAM_DEFAULT_COMP_ALGORITHM="zstd"' \
    'CONFIG_ZRAM_DEFAULT_RECOMP_ALGORITHM="zstd"' \
    "CONFIG_DEBUG_FS=y" \
    "CONFIG_DETECT_HUNG_TASK=y" \
    "CONFIG_FTRACE_SYSCALLS=y" \
    "CONFIG_PID_MAX_CLAMP_BIONIC=y" \
    "CONFIG_KSM=y" \
    "CONFIG_TRANSPARENT_HUGEPAGE=y" \
    "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y"
do
    if grep -q "^$opt" "$DEFCONFIG"; then
        echo "  [OK] $opt"
    else
        echo "  [FAIL] Missing: $opt"
        MISSING=$((MISSING + 1))
    fi
done

if [ "$MISSING" -ne 0 ]; then
    echo "ERROR: $MISSING configuration options failed to apply!"
    exit 1
fi

echo "=== All 30 kernel optimizations verified successfully in sweet_defconfig!"
