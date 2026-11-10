# Kernel Engineering Documentation: los_kernel_xiaomi_sm6150

**Repository:** `los_kernel_xiaomi_sm6150`  
**Device:** Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`)  
**SoC:** Qualcomm Snapdragon 732G (SM6150)  
**Kernel Base:** Linux 4.14.357 (LineageOS / Android 14)  
**Git Branch:** `stable` | **Commit:** `0aaaf8535`  

---

## Directory Overview & Documentation Map

This directory contains the engineering reports, empirical benchmarks, hardware telemetry, reproduction scripts, and architectural analysis generated under the **Master Engineering Directive**.

### 1. Core Engineering Reports
- [FINAL_REPORT.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/FINAL_REPORT.md)  
  *The authoritative final engineering report covering Perspective 1 (Device Efficiency) and Perspective 2 (Ecosystem Synergy).*
- [ARCHITECTURE.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/ARCHITECTURE.md)  
  *Detailed hardware topology, CPU microarchitecture (Kryo 470 Gold/Silver), Adreno 618 KGSL, ZRAM multi-comp, and container virtualization architecture.*
- [BASELINE.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/BASELINE.md)  
  *Original baseline measurements, empirical GLib PIDFD defect reproduction, and stock governor benchmarks.*
- [OPTIMIZATION_LOG.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/OPTIMIZATION_LOG.md)  
  *Complete log of kernel source changes, defconfig flags, problems solved, and technical mechanisms.*
- [BENCHMARKS.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/BENCHMARKS.md)  
  *Comprehensive benchmark tables comparing `schedutil`, `vorpal` (daily), `vorpal` (gaming), and `reflex` on token generation, prompt evaluation, power draw, and memory.*
- [THERMAL_ANALYSIS.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/THERMAL_ANALYSIS.md)  
  *Thermal sensor mappings, junction temperatures, thermal equilibrium analysis, and elimination of thermal throttling.*
- [BATTERY_ANALYSIS.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/BATTERY_ANALYSIS.md)  
  *PMIC telemetry, power-per-watt efficiency, tokens-per-Joule, and 5,020 mAh battery runtime projections.*
- [ECOSYSTEM_ANALYSIS.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/ECOSYSTEM_ANALYSIS.md)  
  *Perspective 2 integration analysis with `Droidspaces-rootfs-Desktop-builder`, `droidspaces-oss`, `anland`, `mesa-for-android-container`, and `mikasa`.*
- [REGRESSION_REPORT.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/REGRESSION_REPORT.md)  
  *Static safety verification, zero-regression audit, and Android backward compatibility guarantees.*
- [STATUS.md](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/STATUS.md)  
  *Project milestone tracking and completion summary.*

---

### 2. Experimental Code & Benchmarking Tools

- [experiments/exp1_pidfd_test.c](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/experiments/exp1_pidfd_test.c):  
  *C reproduction harness demonstrating the `waitid(P_PIDFD)` failure (`EINVAL 22`) on unpatched kernels.*
- [scripts/governor_benchmark.py](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/scripts/governor_benchmark.py):  
  *Automated Python test harness measuring power, thermals, and LLM token generation across CPU governors.*
- [scripts/run_one_bench.sh](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/scripts/run_one_bench.sh):  
  *Root shell helper that bypasses Android `/foreground` cpuset masking and executes workloads with `top-app` dual-core Gold affinity (`c0`).*
- [benchmarks/governor_benchmark_results.json](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/benchmarks/governor_benchmark_results.json):  
  *Raw JSON telemetry output from live Snapdragon 732G testing.*

---

## Key Results Quick Summary

| Metric | Stock Baseline (`schedutil`) | Optimized Configuration (`vorpal_daily` + ZSTD) | Delta / Improvement |
|:---|:---:|:---:|:---:|
| **Peak Power Draw** | 3,811.9 mW | **2,412.1 mW** | **-36.7% (-1.40 W)** |
| **Sustained Token Speed** | 9.23 t/s (Throttled) | **10.18 t/s** (Stable 1.94 GHz) | **+10.3% faster** |
| **Thermal Surge ($\Delta T$)** | +20.1°C (64.1°C peak) | **+6.2°C** (49.2°C peak) | **-69.2% heat rise** |
| **Autonomous Battery Life** | 7.02 hours | **11.23 hours** | **+4.21 hours (+60%)** |
| **ZRAM Compression Density** | 3.1:1 (LZ4) | **10.74:1 (ZSTD)** | **+246% virtual swap capacity** |
| **Container Zombie Reaping** | Broken (leaks zombies) | **Fixed (`P_PIDFD` implemented)** | **Native PIDFD support** |
| **32-bit Bionic TID Limit** | Unbounded (vulnerable) | **Clamped to 65535** | **HAL crash protection** |
