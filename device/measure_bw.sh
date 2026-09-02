#!/system/bin/sh
# measure_bw.sh — Mesurer la bande passante LPDDR pendant le decode
# Mesure bus_access, mem_access, l2d_cache_refill, stall_backend_mem
#
# Usage: adb shell "su -c 'sh /data/local/tmp/measure_bw.sh'"

export LD_LIBRARY_PATH=/data/local/tmp/npu/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/npu/lib
BENCH=/data/local/tmp/npu/llama-bench
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf

echo "=== MEASURE LPDDR BANDWIDTH — $(date) ==="
echo ""

# Kill stale
killall llama-bench 2>/dev/null
sleep 2

# === TEST 1: CPU baseline (ngl=0) — tous les weights en LPDDR ===
echo "=== TEST 1: CPU 8t (ngl=0) ==="
echo "--- PMU counters (during 30s bench) ---"
$BENCH -m $MODEL -p 512 -n 32 -r 1 -ngl 0 -t 8 > /dev/null 2>&1 &
BENCH_PID=$!
sleep 1
simpleperf stat -e armv8_pmuv3/bus_access,armv8_pmuv3/mem_access,armv8_pmuv3/l2d_cache_refill,armv8_pmuv3/l2d_cache_wb,armv8_pmuv3/stall_backend_mem,armv8_pmuv3/l2d_cache_lmiss_rd -p $BENCH_PID -- sleep 28 2>&1
wait $BENCH_PID 2>/dev/null
echo ""

# === TEST 2: HTP batched (ngl=99) ===
echo "=== TEST 2: HTP batched (ngl=99) ==="
echo "--- PMU counters (during 30s bench) ---"
$BENCH -m $MODEL -p 512 -n 32 -r 1 -ngl 99 --device HTP0 > /dev/null 2>&1 &
BENCH_PID=$!
sleep 1
simpleperf stat -e armv8_pmuv3/bus_access,armv8_pmuv3/mem_access,armv8_pmuv3/l2d_cache_refill,armv8_pmuv3/l2d_cache_wb,armv8_pmuv3/stall_backend_mem,armv8_pmuv3/l2d_cache_lmiss_rd -p $BENCH_PID -- sleep 28 2>&1
wait $BENCH_PID 2>/dev/null
echo ""

# === TEST 3: System-wide pendant HTP decode ===
echo "=== TEST 3: System-wide PMU pendant HTP decode ==="
echo "--- PMU counters system-wide ---"
$BENCH -m $MODEL -p 512 -n 32 -r 1 -ngl 99 --device HTP0 > /dev/null 2>&1 &
BENCH_PID=$!
sleep 2
simpleperf stat -e armv8_pmuv3/bus_access,armv8_pmuv3/mem_access,armv8_pmuv3/l2d_cache_refill,armv8_pmuv3/stall_backend_mem -a -- sleep 25 2>&1
wait $BENCH_PID 2>/dev/null
echo ""

echo "=== MEASUREMENT COMPLETE ==="
