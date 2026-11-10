# Empirical Benchmarks: los_kernel_xiaomi_sm6150

**Repository:** `los_kernel_xiaomi_sm6150`  
**SoC:** Qualcomm Snapdragon 732G (SM6150)  
**Target Hardware:** Xiaomi Redmi Note 10 Pro (`sweet`)  
**Test Date:** November 2026  
**Benchmarking Harness:** [governor_benchmark.py](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/scripts/governor_benchmark.py) & [run_one_bench.sh](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/scripts/run_one_bench.sh)  
**Raw Telemetry Data:** [governor_benchmark_results.json](file:///data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/benchmarks/governor_benchmark_results.json)  

---

## 1. Test Methodology & Environment

All benchmarks were executed directly on the physical Snapdragon 732G silicon under strictly controlled conditions:
- **Workload:** High-performance quantized LLM inference using native ARMv8.2-A FP16/DotProd vectorized instructions (`llama-bench` evaluating Qwen2.5-1.5B Q4_K_M).
- **Inference Parameters:** Prompt Processing (`pp512`: 512 tokens) and Token Generation (`tg128`: 128 tokens) across 2 threads pinned exclusively to Gold Cortex-A76 cores.
- **Affinity & Cpuset Configuration:** Executed within Android cgroup `/dev/cpuset/top-app` with exact CPU hex mask `c0` (CPUs 6 & 7) to bypass Android `/foreground` single-core masking.
- **Telemetry Gathering:** High-frequency polling of battery current/voltage via `/sys/class/power_supply/battery/current_now` and `voltage_now` (power in mW), and SoC junction temperatures via thermal zones 0–80 (specifically `msm_therm` and `cpu-1-0-usr` / `cpu-1-1-usr`).

---

## 2. Benchmark Results Summary

| Benchmark Metric | `schedutil` (Baseline) | `vorpal` (Daily / Efficiency) | `vorpal` (Gaming / Burst) | `reflex` | Best Performing Configuration |
|:---|:---:|:---:|:---:|:---:|:---|
| **Prompt Processing Speed** | 32.47 t/s | 29.68 t/s | **35.05 t/s** | 32.77 t/s | **vorpal (Gaming)** (+7.9%) |
| **Token Generation Speed** | 9.23 t/s | **10.18 t/s** | 8.31 t/s | 7.54 t/s | **vorpal (Daily)** (+10.3%) |
| **Total Test Duration** | 21.81 s | 22.36 s | **17.90 s** | 21.52 s | **vorpal (Gaming)** (-17.9% latency) |
| **Resting / Idle Power** | 1,223.9 mW | **778.0 mW** | 1,739.6 mW | 745.5 mW | **vorpal (Daily)** (-36.4%) |
| **Peak Active Power** | 3,811.9 mW | **2,412.1 mW** | 3,874.2 mW | 4,213.6 mW | **vorpal (Daily)** (-36.7% / -1.4W) |
| **Average Power Draw** | 2,752.1 mW | **1,720.8 mW** | 2,920.4 mW | 2,510.8 mW | **vorpal (Daily)** (-37.5%) |
| **Total Energy Consumed** | 16.67 mWh | **10.69 mWh** | 14.52 mWh | 15.00 mWh | **vorpal (Daily)** (-35.9% energy) |
| **Starting Temperature** | 44.0°C | 43.0°C | 47.0°C | 52.0°C | Ambient / Normalized |
| **Peak Temperature** | 64.1°C | **49.2°C** | 61.0°C | 61.7°C | **vorpal (Daily)** (Controlled) |
| **Temperature Rise ($\Delta T$)** | +20.1°C | **+6.2°C** | +14.0°C | +9.7°C | **vorpal (Daily)** (-69.2% heat surge) |
| **Thermal Throttling Event** | **Observed** (1.7 GHz) | **None** (Solid 1.94 GHz) | Moderate (2.0 GHz) | Moderate (1.8 GHz) | **vorpal (Daily)** (Zero throttling) |

---

## 3. Deep-Dive Performance Analysis

### A. The Sustained Throughput Paradox: Why Vorpal Daily is Faster
A critical finding from this hardware benchmark is that `vorpal_daily` delivers **+10.3% faster token generation (10.18 t/s vs 9.23 t/s)** than `schedutil`, despite consuming **36.7% less peak power** (2,412 mW vs 3,812 mW).

- **The Schedutil Failure Mode:**  
  `schedutil` responds aggressively to incoming CPU load, immediately scaling the Kryo 470 Gold cores to their maximum frequency of 2.304 GHz. At 2.304 GHz, dynamic power dissipation spikes to ~3.8W, driving junction temperatures up by **+20.1°C** in less than 15 seconds. The Qualcomm MSM thermal engine and kernel thermal core intervene, aggressively throttling core frequencies down to 1.708 GHz to prevent silicon overheating. During the critical token generation phase, cores are trapped at 1.7 GHz, dragging throughput down to 9.23 t/s.
- **The Vorpal Daily Operating Point:**  
  `vorpal_daily` caps frequency scaling at a highly efficient sweet spot (1.94 GHz) with relaxed up-scaling delays. At 1.94 GHz, the CPU cores operate near their peak efficiency curve (performance-per-watt sweet spot). Temperatures rise by only **+6.2°C**, never triggering thermal trip points. The cores sustain a continuous, stable 1.94 GHz throughout the entire generation phase, outperforming the throttled baseline by over 1 token per second.

```
Schedutil Frequency Profile:
2.30 GHz |========\
1.94 GHz |         \
1.70 GHz |          \============================= (Throttled, 9.23 t/s)
         +----------------------------------------> Time

Vorpal Daily Frequency Profile:
2.30 GHz |
1.94 GHz |======================================== (Sustained, 10.18 t/s)
1.70 GHz |
         +----------------------------------------> Time
```

### B. Prompt Evaluation (Burst Performance)
For short, burst-heavy tasks where latency is paramount (such as UI interaction, instant app launches, or prompt token encoding):
- `vorpal_gaming` achieved **35.05 t/s** (a 7.9% improvement over `schedutil` at 32.47 t/s).
- It completed the complete test in **17.90 seconds**, compared to 21.81 seconds on `schedutil` (a 17.9% reduction in total task latency).
- Cost: Higher idle power (1,739 mW) and peak draw (3,874 mW). Ideal for short interactive bursts, but suboptimal for prolonged background workloads.

---

## 4. Hardware Memory & Swap Benchmarks

| Metric | Stock Configuration (LZ4) | Optimized Configuration (ZSTD) | Improvement |
|:---|:---:|:---:|:---|
| **ZRAM Compression Algorithm** | `lz4` | `zstd` | Modern entropy encoder |
| **Measured Compression Ratio** | 3.1:1 | **10.74:1** | **3.46x denser** |
| **Effective Swap Capacity** | ~3.0 GiB | **>7.5 GiB** | **+150% virtual headroom** |
| **Swap Thrashing Under LLM Load** | 6.5–7.7 MB/s continuous (591 MB/s burst) | <0.1 MB/s (Near Zero) | **Eliminated swap thrashing** |
| **Out-Of-Memory (OOM) Invocations** | Frequent under multi-container load | Zero observed | **Production stability** |

---

## 5. Summary of Recommended Profiles

1. **Daily / Autonomous / Background AI Profile (`vorpal_daily`):**
   - Recommended for daily operation, background agents, and sustained LLM generation.
   - Saves 1.4W peak power, runs 13.9°C cooler, and produces 10.18 tokens/sec.
2. **Interactive / Burst Profile (`vorpal_gaming`):**
   - Recommended for gaming, compiler compilation spikes, and real-time interactive UI.
   - Lowest total execution latency (17.90s), prompt encoding at 35.05 tokens/sec.
