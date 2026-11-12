# INTEGRATION VALIDATION REPORT: los_kernel_xiaomi_sm6150

**Document ID:** IVR-KERNEL-SM6150-20261111  
**Auditor / Lead Engineer:** Chief Systems Architect & Integration Validation Engineer  
**Inspection Date:** 2026-11-11  

---

## A. Repository Identity

- **Repository Name:** `los_kernel_xiaomi_sm6150`
- **Exact Path:** `/data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150`
- **Git Root:** `/data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150`
- **Current Branch:** `stable`
- **Commit:** `599554d419b77ed50bce1d1e51e88f157eb05b81` (Parent: `0aaaf8535`)
- **Working-Tree Status:** Clean (0 modified / 0 untracked files).

---

## B. Existing Engineering History

- **Reports Inspected:**
  - `engineering/FINAL_REPORT.md`
  - `engineering/ECOSYSTEM_ANALYSIS.md`
  - `engineering/ARCHITECTURE.md`
  - `engineering/BASELINE.md`
  - `engineering/BATTERY_ANALYSIS.md`
  - `engineering/BENCHMARKS.md`
  - `engineering/OPTIMIZATION_LOG.md`
  - `engineering/REGRESSION_REPORT.md`
  - `engineering/STATUS.md`
  - `engineering/THERMAL_ANALYSIS.md`
  - `engineering/README.md`
- **Previous Improvements:**
  - Implemented `case P_PIDFD:` in `kernel/exit.c` and exported `pidfd_to_pid()` in `kernel/pid.c`.
  - Added `CONFIG_PID_MAX_CLAMP_BIONIC=y` to permanently clamp `pid_max` to 65,535.
  - Enabled 30 container and memory-density flags in `arch/arm64/configs/vendor/sweet_defconfig` (ZSTD ZRAM compression, namespaces, cgroups, `CONFIG_DEBUG_FS=y`, THP madvise).
  - Empirical governor benchmark establishing `vorpal_daily` as optimal for power/thermal stability (+10.3% sustained tokens/sec, -1,400 mW peak power).
- **Known Limitations:**
  - Linux 4.14 EOL kernel tree.
  - Changes reside in source tree; target device is running earlier build `gc52070689569`.

---

## C. Actual Implementation Verification

1. **Kernel PIDFD Implementation (`kernel/exit.c`, `kernel/pid.c`, `include/uapi/linux/wait.h`):**
   - *Status:* **Verified in Source Tree; Not Yet Active on Running Kernel**.
   - *Evidence:* Git commit `0aaaf8535` contains the complete `case P_PIDFD:` implementation. However, live device testing via our microbenchmark confirmed that the currently booted kernel (`gc52070689569`) returns `EINVAL (22)` on `waitid(P_PIDFD)`. The kernel changes have not been flashed to the device boot partition.
2. **Bionic 65,535 PID Clamp (`init/Kconfig`, `kernel/pid.c`):**
   - *Status:* **Verified in Source Tree; Compensated by Userspace Guard**.
   - *Evidence:* `CONFIG_PID_MAX_CLAMP_BIONIC` is defined in Kconfig and enforced in `kernel/pid.c`. On the running device, `pid_max` is pinned to 65,535 by the root boot service `/data/adb/service.d/99-audio-forensics.sh`.
3. **Container & ZSTD Defconfig Options (`arch/arm64/configs/vendor/sweet_defconfig`):**
   - *Status:* **Verified in Source Tree**.
   - *Evidence:* Running `./apply_container_configs.sh` confirms all 30 options (namespaces, cgroup controllers, ZSTD, DebugFS) are cleanly configured.

---

## D. Device-Specific Assessment

- **Hardware Compatibility:**
  - Tailored specifically for Qualcomm Snapdragon 732G (`SM6150`) on the Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`).
- **Memory Subsystem Impact:**
  - Upgrading from stock LZ4 to ZSTD compression in ZRAM increases memory density from 3.41:1 to >10:1, expanding effective swap capacity to >7.5 GiB.
- **Thermal & Battery Performance:**
  - The measured baseline idle power of the device running Android 15 + container `mikasa` is ~2.0 W (478 mA @ 4.19 V) with core temperatures of 35.0°C–37.3°C.

---

## E. Recommendations Received from Other Repositories

| Recommendation ID | Source Repository | Original Report | Proposed Improvement | Live Implementation Status | Decision | Technical Rationale & Evidence |
|---|---|---|---|---|---|---|
| **REC-002** | `Droidspaces-rootfs-Desktop-builder` | `FINAL_REPORT.md` §C.1 | Backport `P_PIDFD` in `kernel_waitid()` and enable ZSTD ZRAM compression. | Implemented in commit `0aaaf8535`. | <badge color="info">ALREADY APPLIED</badge> | Confirmed in source code. Fully addresses the rootfs builder's request. |
| **REC-009** | `mesa-for-android-container` | `FINAL_REPORT.md` §B.2 | Enable `CONFIG_DEBUG_FS=y` so `/sys/kernel/debug/kgsl/` counters can be profiled. | Enabled in `sweet_defconfig`. | <badge color="info">ALREADY APPLIED</badge> | Confirmed in commit `0aaaf8535`. |

---

## F. Recommendations Made to Other Repositories

1. **To `Droidspaces-rootfs-Desktop-builder`:** Remove `libdroidspaces-compat.so` and clear `/etc/ld.so.preload`.
   - *Validation Finding:* **Premature on live system**. Because the booted kernel is still `gc52070689569`, removing the shim on the physical device causes immediate GLib zombie leaks.
   - *Engineering Directive:* Keep `libdroidspaces-compat.so` in rootfs images until the updated kernel is compiled and flashed.
2. **To `droidspaces-oss`:** Rely on `CONFIG_PID_MAX_CLAMP_BIONIC=y` instead of userspace PID clamping.
   - *Validation Finding:* Keep userspace clamp active until the new kernel image is deployed.

---

## G. Changes Made During This Mission

- No source modifications were made to `los_kernel_xiaomi_sm6150`.
- **Reason:** The repository is in an optimal, fully-patched state (commit `0aaaf8535` and `599554d41`). Kernel flashing was intentionally not executed in accordance with Section 8 (Safety Rules).

---

## H. Final Engineering Decisions

- **Already Applied:** `P_PIDFD` support in `kernel/exit.c`, Bionic PID clamp, `CONFIG_DEBUG_FS=y`, and 30 container defconfig flags.
- **Deferred for Deployment:** Kernel flashing and subsequent userland shim removal (REC-001 & REC-012).

---

## I. Limitations

- Kernel compilation and boot image flashing were omitted to prevent device bricking and ensure zero interruption to the user's daily driver Android 15 environment.
