#!/system/bin/sh
# Run HTP0 benchmark + check NPU activity during workload
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

M=/data/local/tmp/Qwen3.5-9B-D2-A.gguf

# Baseline dmesg fastrpc count
DM0=$(dmesg 2>/dev/null | grep -ci 'fastrpc' || echo 0)
echo "=== Before: fastrpc_dmesg=$DM0 ==="

# Start benchmark
./llama-bench -m $M -ngl 99 -p 16 -n 32 -t 8 -dev HTP0 > /data/local/tmp/bench_npu_check.log 2>&1 &
BPID=$!

# Check NPU activity during run
for i in 1 2 3 4; do
  sleep 10
  DM=$(dmesg 2>/dev/null | grep -ci 'fastrpc' || echo 0)
  T=$(sh /data/local/tmp/gpu_temp.sh 2>/dev/null)
  TS=$(ls -la /dev/fastrpc-cdsp 2>/dev/null | awk '{print $6, $7, $8}')
  echo "t+$((i*10))s fastrpc_dmesg=$DM (delta $((DM-DM0))) $T cdsp_ts=$TS"
done

wait $BPID
DM1=$(dmesg 2>/dev/null | grep -ci 'fastrpc' || echo 0)
echo "=== After: fastrpc_dmesg=$DM1 (delta $((DM1-DM0))) ==="
echo "=== Result ==="
grep -E '^\| qwen.*tg' /data/local/tmp/bench_npu_check.log 2>/dev/null | tail -2