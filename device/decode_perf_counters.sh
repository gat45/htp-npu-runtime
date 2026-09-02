#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu

FTRACE=/sys/kernel/tracing
RESULT=/data/local/tmp/bench_results
mkdir -p $RESULT

echo "=== CONFIGURE ftrace ==="
echo 0 > $FTRACE/tracing_on
echo 131072 > $FTRACE/buffer_size_kb 2>/dev/null
echo "" > $FTRACE/trace

# Enable fastrpc_perf_counters (the KEY event!)
echo 1 > $FTRACE/events/fastrpc/fastrpc_perf_counters/enable

# Also enable fastrpc_msg for detailed phase timing
echo 1 > $FTRACE/events/fastrpc/fastrpc_msg/enable

# Enable arm_smmu for SMMU mapping events
echo 1 > $FTRACE/events/arm_smmu/map_pages/enable
echo 1 > $FTRACE/events/arm_smmu/unmap_pages/enable

echo "ftrace enabled (fastrpc_perf_counters + fastrpc_msg + arm_smmu)"
echo "launching bench..."
echo 1 > $FTRACE/tracing_on

# Run bench: 9B Q4_0, HTP0 only, 32 tokens, 3 repetitions
/data/local/tmp/npu/llama-bench \
  -m /data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf \
  -ngl 99 -t 8 -n 32 -r 3 \
  -dev HTP0 \
  2>&1 | tee $RESULT/perf_bench.txt

echo ""
echo "=== BENCH DONE ==="
echo 0 > $FTRACE/tracing_on

echo "=== SAVING ==="
cp $FTRACE/trace $RESULT/perf_ftrace_full.txt

echo "=== COUNTS ==="
echo "perf_counters: $(grep -c fastrpc_perf_counters $RESULT/perf_ftrace_full.txt)"
echo "fastrpc_msg: $(grep -c fastrpc_msg $RESULT/perf_ftrace_full.txt)"
echo "map_pages: $(grep -c map_pages $RESULT/perf_ftrace_full.txt)"

# Extract perf_counters lines
grep "fastrpc_perf_counters" $RESULT/perf_ftrace_full.txt > $RESULT/perf_counters_only.txt
echo "perf_counters lines: $(wc -l < $RESULT/perf_counters_only.txt)"

# Show first 10
echo "=== FIRST 10 PERF_COUNTERS ==="
head -10 $RESULT/perf_counters_only.txt

# Disable events
echo 0 > $FTRACE/events/fastrpc/fastrpc_perf_counters/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_msg/enable
echo 0 > $FTRACE/events/arm_smmu/map_pages/enable
echo 0 > $FTRACE/events/arm_smmu/unmap_pages/enable

echo "=== DONE ==="
