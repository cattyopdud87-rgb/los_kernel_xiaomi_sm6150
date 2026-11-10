#!/bin/sh
echo $$ > /dev/cpuset/top-app/cgroup.procs
exec taskset c0 /data/data/com.termux/files/home/development/build/llama.cpp/build/bin/llama-bench -m /data/data/com.termux/files/home/development/model/llm/qwen2.5-1.5b-instruct-q4_k_m.gguf -n 64 -p 128 -t 2 -r 1 -o json
