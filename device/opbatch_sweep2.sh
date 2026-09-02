#!/system/bin/sh
BENCH=/data/local/tmp/geniex-bench
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/llama_cpp
export ADSP_LIBRARY_PATH=/data/local/tmp/geniex/lib
RESULT=/data/local/tmp/opbatch_results.txt

echo "=== OPBATCH SWEEP $(date) ===" > $RESULT

run_test() {
    local label=$1
    echo "--- $label ---" >> $RESULT
    timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed" >> $RESULT
    echo "" >> $RESULT
}

echo "1/7 BASELINE"
run_test "BASELINE"

echo "2/7 OPBATCH=2048"
GGML_HEXAGON_OPBATCH=2048 run_test "OPBATCH=2048"
unset GGML_HEXAGON_OPBATCH

echo "3/7 OPBATCH=512"
GGML_HEXAGON_OPBATCH=512 run_test "OPBATCH=512"
unset GGML_HEXAGON_OPBATCH

echo "4/7 OPBATCH=256"
GGML_HEXAGON_OPBATCH=256 run_test "OPBATCH=256"
unset GGML_HEXAGON_OPBATCH

echo "5/7 OPQUEUE=32"
GGML_HEXAGON_OPQUEUE=32 run_test "OPQUEUE=32"
unset GGML_HEXAGON_OPQUEUE

echo "6/7 OPBATCH=2048+OPQUEUE=32"
GGML_HEXAGON_OPBATCH=2048 GGML_HEXAGON_OPQUEUE=32 run_test "OB2048+OQ32"
unset GGML_HEXAGON_OPBATCH
unset GGML_HEXAGON_OPQUEUE

echo "7/7 VERBOSE+OPBATCH=2048"
GGML_HEXAGON_VERBOSE=1 GGML_HEXAGON_OPBATCH=2048 timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "op batching|n-ops|n-bufs|n-tensors|vmem|\[ok\]|ABORT" >> $RESULT

echo "=== DONE ===" >> $RESULT
cat $RESULT
