# KERNEL ENGINEERING BASELINE MEASUREMENTS

**Repository:** `los_kernel_xiaomi_sm6150`  
**Platform:** Qualcomm SM6150 (Snapdragon 732G) | Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`)  
**Operating System:** Android 15 (SDK 35), LineageOS "reforge"  
**Live Kernel:** Linux 4.14.357-reforge-gc52070689569 aarch64  
**Date:** 2026-11-10  

---

## 1. Hardware & System Baseline Environment

| Parameter | Measured Specification |
| :--- | :--- |
| **SoC** | Qualcomm Snapdragon 732G (SM6150 / SDMMAGPIE) |
| **CPU Architecture** | 8 cores: 2× Kryo 470 Gold (Cortex-A76 @ 2.304 GHz) + 6× Kryo 470 Silver (Cortex-A55 @ 1.804 GHz) |
| **CPU ISA Features** | `fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp` |
| **Physical RAM** | 5,654,864 kB (~5.4 GiB kernel-visible) |
| **Swap / ZRAM** | 3,145,724 kB (3.0 GiB zram disksize) formatted with `lz4` |
| **Active Cgroups** | `cpuset`, `cpu`, `cpuacct`, `schedtune`, `blkio`, `memory`, `freezer`, `pids` (cgroup v1 hierarchy) |
| **GPU / Acceleration** | Qualcomm Adreno 618 with KGSL driver (`/dev/kgsl-3d0`) |
| **Thermal Telemetry** | 107 thermal zones (`pm6150-tz`, `cpu-0-2-usr`, `gpuss-0-usr`, etc.) |
| **Power Telemetry** | High-precision microamp/microvolt telemetry via `/sys/class/power_supply/battery/` |

---

## 2. Kernel Source & Defconfig Status Baseline

Inspected `arch/arm64/configs/vendor/sweet_defconfig` (HEAD `9d63f2308`):
* `CONFIG_CRYPTO_ZSTD`: **DISABLED** (`# CONFIG_CRYPTO_ZSTD is not set`).
* `CONFIG_DEBUG_FS`: **DISABLED** (`# CONFIG_DEBUG_FS is not set`).
* `CONFIG_DETECT_HUNG_TASK`: **DISABLED** (`# CONFIG_DETECT_HUNG_TASK is not set`).
* `CONFIG_FTRACE_SYSCALLS`: **DISABLED** (`# CONFIG_FTRACE_SYSCALLS is not set`).
* `CONFIG_KSM`: **DISABLED** (`# CONFIG_KSM is not set`).
* `CONFIG_TRANSPARENT_HUGEPAGE`: **DISABLED** (`# CONFIG_TRANSPARENT_HUGEPAGE is not set`).
* `CONFIG_CGROUP_DEVICE`: **DISABLED** (`# CONFIG_CGROUP_DEVICE is not set`).
* `kernel/exit.c`: Missing `P_PIDFD` (3) case in `kernel_waitid()`.
* `include/uapi/linux/wait.h`: Missing `#define P_PIDFD 3`.
* `kernel/pid.c`: `pid_max_max` defaults to `PID_MAX_LIMIT` (4M) without 32-bit vendor HAL safeguard.

---

## 3. Discovered Defects: Reproduction Baselines

### 3.1 GLib PIDFD Zombie Defect Reproduction (`exp1_pidfd_test`)
Tested live on device using standalone C test harness:
```
=== PIDFD & WAITID P_PIDFD REPRODUCTION BENCHMARK ===
1. pidfd_open(pid=39911) returned: fd=4 (errno=2: No such file or directory)
2. Calling waitid(P_PIDFD=3, pidfd=4, WEXITED)...
3. waitid(P_PIDFD) returned: -1 (errno=22: Invalid argument)
>>> CONFIRMED DEFECT: Kernel returned EINVAL (22)! P_PIDFD is missing in kernel_waitid!
4. Fallback waitpid(pid=39911) cleaned up child (exit code=42)
```
* **Status:** Confirmed. Syscall 434 (`pidfd_open`) succeeds, but `waitid(P_PIDFD=3)` fails with `EINVAL (22)`, preventing modern container userspace (systemd, GLib 2.74+) from reaping child processes.

### 3.2 32-bit Bionic TID Limit & Audio HAL Mutex Failure
* In 32-bit bionic libc, `pthread_mutex_t` encodes owner TID in 16 bits.
* Any TID > 65,535 triggers immediate SIGABRT: `32-bit pthread_mutex_t only supports pids <= 65535; current pid X; echo 65535 > /proc/sys/kernel/pid_max`.
* When `pid_max` is set to 4M, the system burns PIDs at ~16 PIDs/sec and crosses 65,535 within 40–60 minutes, crashing `audio.primary.sm6150.so` and `crash_dump32`.

---

## 4. CPUFreq Governors Live Baseline Benchmark

Workload: Quantized LLM Inference (`qwen2.5-1.5b-instruct-q4_k_m.gguf`, pp128, tg64, 2 threads) pinned to Gold cluster (Cores 6, 7) in `/dev/cpuset/top-app` with affinity mask `c0`.

| Governor & Profile | Prompt Eval (t/s) | Generation (t/s) | Total Elapsed (s) | Peak Power (mW) | Temp Delta (°C) | Operating Characteristics |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`schedutil` (Stock Default)** | 32.47 t/s | 9.23 t/s | 21.81 s | 3,811.9 mW | **+20.1 °C** (44.5 → 64.6 °C) | High thermal dissipation (+20.1°C), causes thermal throttling down to 1.7 GHz during prolonged load. |
| **`vorpal` (Daily Profile)** | 29.68 t/s | **10.18 t/s** | 22.36 s | **2,412.1 mW** | **+6.2 °C** (48.7 → 54.9 °C) | **Optimal Efficiency & Sustained Throughput.** Reduces power consumption by **36.7% (-1,400 mW)**, keeps CPU **14°C cooler**, and yields 10.3% faster steady generation. |
| **`vorpal` (Gaming Profile)** | **35.05 t/s** | 8.31 t/s | **17.90 s** | 3,874.2 mW | +14.0 °C (47.7 → 61.7 °C) | **Maximum Burst Performance.** Fastest prompt evaluation (35.05 t/s), shortest completion time (17.90 s). Instantaneous ramp to 2.304 GHz. |
| **`reflex` (Fast Rising Edge)** | 32.77 t/s | 7.54 t/s | 21.52 s | 745.5 mW (rest) | +9.7 °C (51.0 → 60.7 °C) | Good prompt latency (32.77 t/s), but conservative steady-state generation speed on SM6150. |

---

## 5. Memory & ZRAM Compression Baseline

| Metric | Measured Baseline Value | Target with ZSTD Crypto |
| :--- | :--- | :--- |
| **Physical RAM Availability** | 520 MB – 1.3 GB available | Stable > 1.8 GB available |
| **ZRAM Compression Algorithm** | `lz4` | `zstd` |
| **ZRAM Compression Density** | **3.11:1 to 4.28:1** | **10.74:1 (2.5× to 3.4× higher density)** |
| **Effective Swap Capacity** | 3.0 GiB (100% full, SwapFree < 1 MB) | **> 7.5 GiB effective anonymous page capacity** |
| **Idle Swap Churn (`kswapd0`)** | **6.5 to 7.7 MB/s** | **< 1.0 MB/s** |
| **AllocStall Events** | 48,726 events | Eliminated via cushion (`vm.min_free_kbytes=32768`) |
