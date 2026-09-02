#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

M=/data/local/tmp/Qwen3.5-9B-D2-A.gguf

echo "=== Start long HTP0 run + GPU monitor ==="
# Start benchmark in background
./llama-bench -m $M -ngl 99 -p 32 -n 32 -t 8 -dev HTP0 > /data/local/tmp/bench_htp0_long.log 2>&1 &
BPID=$!

# Monitor GPU util + temp while it runs
for i in 1 2 3 4 5 6; do
  sleep 15
  G=$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null || echo "?")
  T=$(sh /data/local/tmp/gpu_temp.sh 2>/dev/null)
  echo "t+$((i*15))s GPU_util=$G $T"
done

wait $BPID
echo "=== Done. GPU_final=$G ==="