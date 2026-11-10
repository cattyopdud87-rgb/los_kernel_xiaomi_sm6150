#!/usr/bin/env python3
"""
Controlled Governor Benchmark for SM6150 (Gold Cluster CPU 6,7)
Tests: schedutil, vorpal (daily), vorpal (gaming), reflex.
Guarantees execution in /dev/cpuset/top-app with affinity c0 (cores 6 and 7).
"""

import subprocess
import time
import json
import os
import sys

CONFIGS = [
    {"name": "schedutil", "gov": "schedutil", "gaming": 0},
    {"name": "vorpal_daily", "gov": "vorpal", "gaming": 0},
    {"name": "vorpal_gaming", "gov": "vorpal", "gaming": 1},
    {"name": "reflex", "gov": "reflex", "gaming": 0},
]

RUNNER_SCRIPT = "/data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/scripts/run_one_bench.sh"

def su_cmd(cmd):
    full_cmd = f"su -c '{cmd}'"
    res = subprocess.run(full_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return res.stdout.strip()

def get_telemetry():
    v = su_cmd("cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0")
    i = su_cmd("cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0")
    t_batt = su_cmd("cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0")
    t_cpu = su_cmd("cat /sys/class/thermal/thermal_zone20/temp 2>/dev/null || echo 0")
    f6 = su_cmd("cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq 2>/dev/null || echo 0")
    f0 = su_cmd("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0")
    
    try:
        uV = float(v)
        uA = float(i)
        power_mW = (uV * uA) / 1e9
    except:
        power_mW = 0.0
        
    return {
        "voltage_uV": float(v) if v else 0,
        "current_uA": float(i) if i else 0,
        "power_mW": power_mW,
        "batt_temp_C": float(t_batt) / 10.0 if t_batt else 0,
        "cpu_temp_C": float(t_cpu) / 1000.0 if t_cpu else 0,
        "freq_cpu6_MHz": float(f6) / 1000.0 if f6 else 0,
        "freq_cpu0_MHz": float(f0) / 1000.0 if f0 else 0,
    }

def setup_governor(cfg):
    gov = cfg["gov"]
    gaming = cfg["gaming"]
    print(f"\n--> Configuring: {cfg['name']} (gov={gov}, gaming={gaming})")
    su_cmd(f"echo {gov} > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    su_cmd(f"echo {gov} > /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor")
    if gov == "vorpal":
        su_cmd(f"echo {gaming} > /sys/devices/system/cpu/cpu6/cpufreq/vorpal/gaming_mode 2>/dev/null || true")
    time.sleep(1)

def run_bench(cfg):
    name = cfg["name"]
    print(f"\n=======================================================")
    print(f"BENCHMARKING: {name.upper()}")
    print(f"=======================================================")
    setup_governor(cfg)
    
    print("Settling CPU for 3 seconds...")
    time.sleep(3)
    
    t_before = get_telemetry()
    print(f"Start State: CPU={t_before['cpu_temp_C']}°C, Batt={t_before['batt_temp_C']}°C, Power={t_before['power_mW']:.1f}mW, Freq6={t_before['freq_cpu6_MHz']}MHz")
    
    t_start = time.time()
    raw_out = su_cmd(RUNNER_SCRIPT)
    duration = time.time() - t_start
    
    t_after = get_telemetry()
    print(f"End State: CPU={t_after['cpu_temp_C']}°C, Batt={t_after['batt_temp_C']}°C, Power={t_after['power_mW']:.1f}mW, Freq6={t_after['freq_cpu6_MHz']}MHz")
    print(f"Elapsed: {duration:.2f}s | CPU Temp Rise: +{t_after['cpu_temp_C'] - t_before['cpu_temp_C']:.1f}°C")
    
    gen_ts = None
    pp_ts = None
    try:
        data = json.loads(raw_out)
        for item in data:
            n_prompt = item.get("n_prompt", 0)
            n_gen = item.get("n_gen", 0)
            avg_ts = item.get("avg_ts", 0)
            if n_prompt > 0 and n_gen == 0:
                pp_ts = avg_ts
            elif n_gen > 0 and n_prompt == 0:
                gen_ts = avg_ts
            elif n_gen > 0 and n_prompt > 0:
                if gen_ts is None:
                    gen_ts = avg_ts
    except Exception as e:
        print(f"Parse warning: {e}")
        print(f"Raw: {raw_out[:200]}")
        
    return {
        "config": cfg,
        "duration_s": duration,
        "generation_ts": gen_ts,
        "prompt_eval_ts": pp_ts,
        "t_before": t_before,
        "t_after": t_after,
        "temp_delta": t_after["cpu_temp_C"] - t_before["cpu_temp_C"],
        "power_mW": t_after["power_mW"],
    }

def main():
    orig_c0 = su_cmd("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    orig_c6 = su_cmd("cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor")
    print(f"Original governors: cpu0={orig_c0}, cpu6={orig_c6}")
    
    results = {}
    try:
        for cfg in CONFIGS:
            res = run_bench(cfg)
            results[cfg["name"]] = res
            print(f"--> {cfg['name']}: Prompt={res.get('prompt_eval_ts', 0):.2f} t/s, Gen={res.get('generation_ts', 0):.2f} t/s, Time={res['duration_s']:.2f}s, Power={res['power_mW']:.1f}mW")
    finally:
        print(f"\nRestoring original governors...")
        su_cmd(f"echo {orig_c0} > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
        su_cmd(f"echo {orig_c6} > /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor")
        
    out_file = "/data/data/com.termux/files/home/development/repo/los_kernel_xiaomi_sm6150/engineering/benchmarks/governor_benchmark_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved benchmark results to {out_file}")

if __name__ == "__main__":
    main()
