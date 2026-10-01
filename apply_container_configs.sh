#!/usr/bin/env bash
set -e

echo "=== Syncing repository with upstream..."
git fetch origin stable
git rebase origin/stable || {
    echo "Rebase conflict detected, attempting auto-applying container defconfig options..."
    git rebase --abort || true
    git pull --rebase origin stable
}

echo "=== Ensuring Droidspaces / LXC kernel options in sweet_defconfig..."
DEFCONFIG="arch/arm64/configs/vendor/sweet_defconfig"

# Enable SYSVIPC & POSIX_MQUEUE
sed -i 's/# CONFIG_SYSVIPC is not set/CONFIG_SYSVIPC=y\nCONFIG_SYSVIPC_SYSCTL=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_POSIX_MQUEUE is not set/CONFIG_POSIX_MQUEUE=y/' "$DEFCONFIG"

# Enable Namespaces (PID, IPC, USER)
sed -i 's/# CONFIG_USER_NS is not set/CONFIG_USER_NS=y/' "$DEFCONFIG"
sed -i 's/# CONFIG_PID_NS is not set/CONFIG_PID_NS=y/' "$DEFCONFIG"
grep -q "CONFIG_IPC_NS=y" "$DEFCONFIG" || sed -i '/CONFIG_UTS_NS=y/a CONFIG_IPC_NS=y' "$DEFCONFIG"

# Enable DEVTMPFS
sed -i 's/# CONFIG_DEVTMPFS is not set/CONFIG_DEVTMPFS=y\nCONFIG_DEVTMPFS_MOUNT=y/' "$DEFCONFIG"

if git diff --quiet "$DEFCONFIG"; then
    echo "All container configs are already present."
else
    echo "Container configs updated. Committing and pushing..."
    git add "$DEFCONFIG"
    git commit -m "defconfig: Enable PID, IPC, DEVTMPFS, and USER_NS for Droidspaces & LXC containers"
    git push origin stable
fi

echo "=== Successfully updated kernel repository!"
