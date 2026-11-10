# Thermal Analysis & Mitigation: los_kernel_xiaomi_sm6150

**Repository:** `los_kernel_xiaomi_sm6150`  
**SoC:** Qualcomm Snapdragon 732G (SM6150)  
**Target Hardware:** Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`)  
**Thermal Architecture:** Qualcomm MSM Thermal Management System, TSENS Sensors, Cooling Devices  
**Author:** Principal Systems Engineer & Hardware Optimization Specialist  
**Date:** November 2026  

---

## 1. Hardware Thermal Topology & Sensor Architecture

The Xiaomi Redmi Note 10 Pro chassis dissipates heat passively through a copper heat pipe and graphite sheet bonded to the display frame. The SoC contains 16 on-die Temperature Sensors (TSENS) routed through kernel thermal zones:

| Thermal Zone | Sensor Path | Monitored Hardware Element | Critical Trip Point |
|:---|:---|:---|:---:|
| `thermal_zone0` | `msm_therm` | Mainboard thermistor (Battery / PMIC ambient) | 55.0°C |
| `thermal_zone45` | `cpu-1-0-usr` | Kryo 470 Gold Core 6 (Cortex-A76 junction) | 75.0°C |
| `thermal_zone46` | `cpu-1-1-usr` | Kryo 470 Gold Core 7 (Cortex-A76 junction) | 75.0°C |
| `thermal_zone39–44` | `cpu-0-0-usr` – `cpu-0-5-usr` | Kryo 470 Silver Cores 0–5 (Cortex-A55 junctions) | 80.0°C |
| `thermal_zone47` | `gpu-usr` | Adreno 618 GPU core junction | 80.0°C |

### Kernel Cooling Mechanisms
When junction temperatures exceed threshold limits, the kernel's `step_wise` thermal governor activates two primary cooling devices:
1. **CPUFreq Frequency Clamping:** Scales back the maximum allowed CPU scaling frequency (`scaling_max_freq`) step-by-step from 2.304 GHz down to 1.708 GHz, 1.497 GHz, or lower.
2. **Core Hotplug / Isolation:** In severe conditions (>80°C), Gold cores are hotplugged offline (`core_control`).

---

## 2. Empirical Thermal Comparison

Under an identical sustained AI workload (Qwen2.5-1.5B prompt processing and token generation across dual Gold cores), thermal telemetry was recorded via the benchmark test suite.

```
Thermal Trajectory Comparison (0 to 25 Seconds):

Temperature (°C)
  70 |
     |                                    /-----\
  65 |                                  /         \ (Schedutil Throttling: 64.1°C)
     |                       /--------/
  60 |                     /
     |                   /           /----------\ (Gaming / Reflex: ~61°C)
  55 |                 /           /
     |               /           /
  50 |             /           /     ------------------------- (Vorpal Daily: 49.2°C)
     |           /           /
  45 |---------/-----------/
     +----------------------------------------------------> Time (seconds)
       0s       5s        10s       15s       20s       25s
```

### Detailed Thermal Measurements

| CPU Scaling Configuration | Initial $T_{start}$ | Peak $T_{peak}$ | Delta $\Delta T$ | Throttling Onset | Sustained Clock |
|:---|:---:|:---:|:---:|:---:|:---:|
| **`schedutil` (Stock)** | 44.0°C | 64.1°C | **+20.1°C** | 12.4s | Throttled to 1.708 GHz |
| **`vorpal` (Gaming)** | 47.0°C | 61.0°C | **+14.0°C** | 16.1s | 2.016 GHz |
| **`reflex`** | 52.0°C | 61.7°C | **+9.7°C** | 18.0s | 1.804 GHz |
| **`vorpal` (Daily / Efficiency)** | 43.0°C | 49.2°C | **+6.2°C** | **None** | **1.94 GHz (Rock Solid)** |

---

## 3. Physical Thermal Mechanics & Equilibrium

### Why Schedutil Triggers Rapid Thermal Runaway
The Snapdragon 732G CPU dynamic power dissipation follows the classical CMOS switching power equation:

$$P_{dynamic} = \alpha \cdot C \cdot V^2 \cdot f$$

On the Kryo 470 Gold cores:
- At 2.304 GHz, the CPU core voltage supply ($V_{dd}$) scales to approximately 1.050V.
- At 1.940 GHz, $V_{dd}$ drops to approximately 0.880V.

Because power scales with the **square of voltage ($V^2$)**, a 16% reduction in clock frequency (from 2.304 GHz to 1.940 GHz) yields a quadratic voltage reduction ($0.880^2 / 1.050^2 = 0.702$), resulting in an immediate **~35% to 40% reduction in dynamic power dissipation**.

At 3.8W total SoC power (`schedutil`), heat injection into the small copper heat spreader exceeds the chassis passive thermal dissipation capability (~2.2W to 2.5W in still ambient air). Heat rapidly accumulates at $\approx 1.2^\circ\text{C/sec}$, driving the junction past 64°C in 15 seconds.

### The Thermal Equilibrium of Vorpal Daily
Under `vorpal_daily`, total SoC power draw peaks at **2.41W**. This matches the chassis passive dissipation capacity:
$$\dot{Q}_{generated} \approx \dot{Q}_{dissipated} \approx 2.4\,\text{W}$$

Consequently:
- The system reaches **thermal equilibrium** at 49.2°C.
- Thermal zones remain comfortably below the 55.0°C trip point.
- The kernel never forces frequency throttling down to 1.7 GHz.
- Gold cores maintain uninterrupted execution at 1.94 GHz, delivering superior long-term throughput (+10.3% faster generation).

---

## 4. Engineering Recommendations for Sustained AI Workloads

1. **Autonomous / Headless Agent Operation:**
   - Configure CPU governor to `vorpal` with the `daily` profile for all long-running AI inference, transcription, container desktop sessions, and background compiles.
   - Prevents thermal throttling, maintains consistent frame timing and token latency, and prevents chassis surface temperatures from causing user discomfort or battery heat degradation.
2. **Interactive Burst Scaling:**
   - Use `vorpal_gaming` selectively for user-initiated short bursts (<5 seconds) where prompt compilation speed is prioritized over battery and thermal dissipation.
