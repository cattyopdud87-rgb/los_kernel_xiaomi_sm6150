#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "=== Ensuring upstream remote is configured..."
if ! git remote | grep -q "^upstream$"; then
    git remote add upstream https://github.com/manipvlator/los_kernel_xiaomi_sm6150.git
fi

echo "=== Fetching upstream stable..."
git fetch --depth=50 upstream stable

echo "=== Backing up current state..."
git branch -f backup-stable-before-sync HEAD

# Keep self script preserved across resets
TMP_SCRIPT="$(mktemp)"
cp "$0" "$TMP_SCRIPT"

echo "=== Resetting onto upstream/stable..."
git reset --hard upstream/stable

cp "$TMP_SCRIPT" "$0"
rm -f "$TMP_SCRIPT"
chmod +x "$0"

echo "=== Applying Droidspaces & Container kernel options in sweet_defconfig..."
DEFCONFIG="arch/arm64/configs/vendor/sweet_defconfig"

# 1. Enable SYSVIPC & POSIX_MQUEUE (IPC dependencies)
sed -i 's/# CONFIG_SYSVIPC is not set/CONFIG_SYSVIPC=y\nCONFIG_SYSVIPC_SYSCTL=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_POSIX_MQUEUE is not set/CONFIG_POSIX_MQUEUE=y/' "$DEFCONFIG"

# 2. Enable CPU and Process limits (CFS_BANDWIDTH & CGROUP_PIDS)
sed -i 's/# CONFIG_CFS_BANDWIDTH is not set/CONFIG_CFS_BANDWIDTH=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_CGROUP_PIDS is not set/CONFIG_CGROUP_PIDS=y/' "$DEFCONFIG"

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

echo "=== Verifying applied configurations..."
MISSING=0
for opt in \
    "CONFIG_SYSVIPC=y" \
    "CONFIG_SYSVIPC_SYSCTL=y" \
    "CONFIG_POSIX_MQUEUE=y" \
    "CONFIG_CFS_BANDWIDTH=y" \
    "CONFIG_CGROUP_PIDS=y" \
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
    "CONFIG_MACVTAP=y"
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

echo "=== All 16 container configurations verified successfully!"

if git diff --quiet "$DEFCONFIG" && git diff --quiet apply_container_configs.sh; then
    echo "No changes needed, already committed."
else
    echo "Creating clean commit..."
    git add "$DEFCONFIG" apply_container_configs.sh
    git -c user.name="kk703338" -c user.email="kk703338@gmail.com" commit -m "defconfig: Enable Droidspaces flags (PID, IPC, USER, DEVTMPFS, MACVLAN, IPv6 NAT, CFS, PIDS)"
    echo "Commit created successfully on top of $(git rev-parse --short upstream/stable)."
fi

echo "=== Successfully updated kernel repository!"
