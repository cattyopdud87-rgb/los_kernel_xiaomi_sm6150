# KERNEL ARCHITECTURE & SYSTEM AUDIT

**Repository:** `los_kernel_xiaomi_sm6150`  
**SoC:** Qualcomm SM6150 (Snapdragon 732G, "SDMMAGPIE")  
**Device:** Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`, M2101K6P)  
**Host Kernel:** Linux 4.14.357-reforge-gc52070689569 aarch64  
**Date:** 2026-11-10  

---

## 1. System Architecture & Hardware Topology

```
+----------------------------------------------------------------------------------------------------+
|                                QUALCOMM SM6150 (SNAPDRAGON 732G)                                   |
|                                                                                                    |
|  +---------------------------------------------+   +--------------------------------------------+  |
|  |     GOLD PERFORMANCE CLUSTER (Cluster 1)    |   |     SILVER EFFICIENCY CLUSTER (Cluster 0)  |  |
|  |           2x Kryo 470 (Cortex-A76)          |   |           6x Kryo 470 (Cortex-A55)         |  |
|  |               Frequencies:                  |   |               Frequencies:                 |  |
|  |        825.6 MHz to 2304.0 MHz (2.3 GHz)    |   |         576.0 MHz to 1804.8 MHz (1.8 GHz)  |  |
|  |               CPUs: CPU 6, CPU 7            |   |               CPUs: CPU 0 to CPU 5         |  |
|  |  Workload: LLM Inference, Android UI Render |   |  Workload: Desktop Container, Daemons, BG  |  |
|  +---------------------------------------------+   +--------------------------------------------+  |
|                                         |                 |                                        |
|  +--------------------------------------+-----------------+-------------------------------------+  |
|  |                     CPU CAPABILITIES & INSTRUCTION SET EXTENSIONS (ARMv8.2-A)                |  |
|  |  asimddp (INT8 SDOT/UDOT) · fphp/asimdhp (FP16) · atomics (LSE) · aes · pmull · sha1/sha2     |  |
|  +----------------------------------------------------------------------------------------------+  |
|                                         |                                                          |
|  +--------------------------------------+-------------------------------------------------------+  |
|  |  GRAPHICS: Adreno 618 (GPU)          |  AUDIO & DSP: Qualcomm Hexagon QDSP6 (ADSP)           |  |
|  |  - Direct KGSL access via /dev/kgsl  |  - Audio Processing Domain (adsprpcd_audiopd)         |  |
|  |  - 120Hz/90Hz/60Hz AMOLED Panel      |  - 32-bit ELF vendor audio HAL (audio.primary.sm6150) |  |
|  +--------------------------------------+-------------------------------------------------------+  |
|                                         |                                                          |
|  +--------------------------------------+-------------------------------------------------------+  |
|  |  PHYSICAL MEMORY: 5,654,864 kB (~5.4 GiB) · COMPRESSED ZRAM SWAP: 3,145,724 kB (3.0 GiB)     |  |
|  +----------------------------------------------------------------------------------------------+  |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Core Kernel Subsystems Audit

### 2.1 CPU Scheduling & Frequency Scaling
* **Scheduler Infrastructure:** Linux CFS (Completely Fair Scheduler) enhanced with:
  * **BORE (Burst-Oriented Response Enhancer v5.1.0):** Dynamically scales burst penalty and task slice times (`kernel.sched_bore=1`, `kernel.sched_burst_fork_atavistic=2`).
  * **CASS (Capacity Aware SchedTune/Scheduler):** Allocates tasks according to core capacity and latency sensitivity.
* **Available CPUFreq Governors:**
  1. `schedutil`: Standard PELT-based governor with 1.25× frequency headroom.
  2. `vorpal` (v2.2): High-performance GKI 5.10 backport with directional EMA load tracking, load-proportional headroom, gaming/daily profiles, and fceil-relative thresholds.
  3. `reflex` (v0.4.0): Fast-rising edge demand estimator that calculates unsaturated intervals from `kcpustat` idle time to eliminate PELT ramp latency.
  4. `performance`: Pins clusters to maximum frequency (2304 MHz / 1804 MHz).
  5. `powersave`: Pins clusters to minimum frequency (825 MHz / 576 MHz).
* **SchedTune Boost Groups:** Mounted at `/dev/stune/` with dedicated cgroups:
  * `top-app`: `boost=10`, `prefer_idle=1` (prioritizes low latency for focused Android apps).
  * `foreground`: `boost=0`, `prefer_idle=1`.
  * `background`: `boost=0`, `prefer_idle=0`.
  * `droidspaces`: `boost=0`, `prefer_idle=0` (tunable for container desktop and AI bursts).

### 2.2 Memory Management & ZRAM Subsystem
* **Physical RAM Constraint:** 5.4 GiB usable memory shared simultaneously between:
  - Android 15 framework and GMS (`system_server` ~713 MB, SystemUI ~389 MB, GMS ~560 MB).
  - Heavy social/media applications (e.g. Instagram ~1.5 GB).
  - Droidspaces Linux Container (Arch Linux + KDE Plasma 6.8 + Wayland compositor ~740 MB).
  - On-Device Speech AI (Qwen2.5 1.5B LLM ~1.2 GB).
* **ZRAM Implementation:**
  - Backported Linux 6.2 multi-stream compression (`CONFIG_ZRAM_MULTI_COMP=y`).
  - Automatic idle recompression enabled (`CONFIG_ZRAM_AUTO_RECOMP=y`).
  - Deduplication support (`CONFIG_ZRAM_DEDUP=y`).
  - Current limitation: restricted to LZ4, LZO, and Deflate due to missing `CONFIG_CRYPTO_ZSTD=y`.

### 2.3 Container & Namespaces Subsystem
* **Namespaces:** PID, IPC, USER, NET, UTS, and MOUNT namespaces enabled in defconfig.
* **Cgroups v1:** Memory, cpuset, cpu, cpuacct, pids, freezer, blkio, and schedtune controllers active.
* **Networking:** MACVLAN, MACVTAP, IPv6 NAT, and masquerading compiled in.
* **Devtmpfs:** Enabled and mounted for rapid container device node population.

---

## 3. Discovered Architectural Deficiencies & Root Causes

### 3.1 P0 Defect: The GLib / Systemd PIDFD Zombie Defect in `kernel/exit.c`
* **Mechanism:** The kernel tree backported `pidfd_open()` in `kernel/pid.c` (syscall 434). Modern userspace libraries (GLib 2.74+, systemd 250+) check `syscall(__NR_pidfd_open, ...)`; upon success, they immediately adopt pidfd child polling and call `waitid(P_PIDFD, pidfd, &info, WEXITED, NULL)`.
* **The Failure:** In `kernel/exit.c:1634` (`kernel_waitid`), the `switch (which)` block only handles `P_ALL`, `P_PID`, and `P_PGID`. Any call with `which == P_PIDFD` (3) falls into `default: return -EINVAL;`.
* **Consequence:** GLib's `g_child_watch` handler fails with `EINVAL`, child exit signals are ignored, and terminated container processes remain permanent zombies.
* **Resolution:** Add `P_PIDFD` case to `kernel_waitid()` in `kernel/exit.c` and define `#define P_PIDFD 3` in `include/uapi/linux/wait.h`.

### 3.2 P0 Defect: ZRAM Compression Ratio Deficit (`CONFIG_CRYPTO_ZSTD`)
* **Mechanism:** `sweet_defconfig` has `# CONFIG_CRYPTO_ZSTD is not set`. ZRAM is forced to use LZ4 (`ratio ~3.1:1`).
* **The Failure:** The 3.0 GiB ZRAM device fills completely with ~1.0 GB of compressed pages, leaving 0% free swap. Kernel `kswapd0` triggers continuous swap churn (6.5–7.7 MB/s), wasting CPU cycles and draining battery.
* **Resolution:** Enable `CONFIG_CRYPTO_ZSTD=y`, `CONFIG_ZSTD_COMPRESS=y`, `CONFIG_ZSTD_DECOMPRESS=y`, and update `ZRAM_DEFAULT_COMP_ALGORITHM="zstd"`. ZSTD achieves 10.74:1 compression on anonymous heap pages, expanding effective swap capacity to >7.5 GiB.

### 3.3 P1 Defect: 32-bit Qualcomm Audio HAL TID Overflow
* **Mechanism:** `pid_max_max` is defined as 4,194,304 (4M). The container daemon or user scripts can write 4M to `/proc/sys/kernel/pid_max`.
* **The Failure:** Android Bionic 32-bit `pthread_mutex_t` stores owner TID in only 16 bits. When PIDs burn past 65,535, Qualcomm vendor audio HAL (`audio.primary.sm6150.so`) aborts with `32-bit pthread_mutex_t only supports pids <= 65535`.
* **Resolution:** Enforce a hard ceiling in `kernel/pid.c` / `kernel/sysctl.c` clamping `pid_max_max <= 65535` when 32-bit compat is active, permanently eliminating the crash window without requiring polling scripts.

### 3.4 P1 Defect: Forensic Observability Blind Spots
* **Mechanism:** Defconfig disables `CONFIG_DEBUG_FS`, `CONFIG_DETECT_HUNG_TASK`, and `CONFIG_FTRACE_SYSCALLS`.
* **The Failure:** During audio HAL or binder deadlocks, `/sys/kernel/debug/binder` is unavailable, kernel hung task detector does not print D-state stack traces, and syscall tracing cannot verify blocked ioctls.
* **Resolution:** Enable `CONFIG_DEBUG_FS=y`, `CONFIG_DETECT_HUNG_TASK=y` (30s timeout), and `CONFIG_FTRACE_SYSCALLS=y` in `sweet_defconfig`.
