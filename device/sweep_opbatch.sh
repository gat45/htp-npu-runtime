#!/bin/sh
# Test sweep of OPBATCH/OPQUEUE/OPSTAGE knobs
# Each test runs geniex-bench with different env vars

BENCH="/data/local/tmp/geniex-bench"
MODEL="/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf"
LIBS="/data/local/tmp:/data/local/tmp/llama_cpp"
ADSP="/data/local/tmp/geniex/lib"

run_test() {
    local label="$1"
    local envvars="$2"
    local logfile="/data/local/tmp/opbatch_${label}.log"
    
    echo "=== TEST: $label ==="
    echo "  env: $envvars"
    
    LD_LIBRARY_PATH=$LIBS ADSP_LIBRARY_PATH=$ADSP \
    $envvars \
    timeout 120 $BENCH --plugin llama_cpp --device npu \
        -m $MODEL -n 8 -p 32 -t 8 2>&1 | tee $logfile
    
    # Extract metrics
    grep -E "tg\d|pp\d|tok/s|batch|ops|vmem|ABORT|failed" $logfile | tail -5
    echo ""
}

# Test 0: Baseline (no special env vars)
run_test "baseline" ""

# Test 1: OPBATCH=2048 (double the default)
run_test "ob2048" "GGML_HEXAGON_OPBATCH=2048"

# Test 2: OPBATCH=512 (half the default)
run_test "ob512" "GGML_HEXAGON_OPBATCH=512"

# Test 3: OPBATCH=256 (quarter)
run_test "ob256" "GGML_HEXAGON_OPBATCH=256"

# Test 4: OPQUEUE=32 (deeper pipeline)
run_test "oq32" "GGML_HEXAGON_OPQUEUE=32"

# Test 5: OPSTAGE=0 (skip compute, queue only)
run_test "os0" "GGML_HEXAGON_OPSTAGE=0"

# Test 6: OPSTAGE=1 (compute only, no queue)
run_test "os1" "GGML_HEXAGON_OPSTAGE=1"

# Test 7: Combined OPBATCH=2048 + OPQUEUE=32
run_test "ob2048_oq32" "GGML_HEXAGON_OPBATCH=2048 GGML_HEXAGON_OPQUEUE=32"

# Summary
echo ""
echo "=== SUMMARY ==="
for f in /data/local/tmp/opbatch_*.log; do
    name=$(basename $f .log)
    tg=$(grep -oP 'tg\d+\s+\|.*\|\s+\K[0-9.]+' $f | tail -1)
    pp=$(grep -oP 'pp\d+\s+\|.*\|\s+\K[0-9.]+' $f | tail -1)
    aborted=$(grep -c "ABORT\|failed" $f 2>/dev/null)
    echo "  $name: pp=$pp tg=$tg aborted=$aborted"
done
