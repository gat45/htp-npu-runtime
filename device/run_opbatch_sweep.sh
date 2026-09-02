#!/system/bin/sh
BENCH=/data/local/tmp/geniex-bench
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/llama_cpp
export ADSP_LIBRARY_PATH=/data/local/tmp/geniex/lib

echo "=== BASELINE ==="
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
echo ""

echo "=== OPBATCH=2048 ==="
export GGML_HEXAGON_OPBATCH=2048
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
unset GGML_HEXAGON_OPBATCH
echo ""

echo "=== OPBATCH=512 ==="
export GGML_HEXAGON_OPBATCH=512
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
unset GGML_HEXAGON_OPBATCH
echo ""

echo "=== OPBATCH=256 ==="
export GGML_HEXAGON_OPBATCH=256
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
unset GGML_HEXAGON_OPBATCH
echo ""

echo "=== OPQUEUE=32 ==="
export GGML_HEXAGON_OPQUEUE=32
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
unset GGML_HEXAGON_OPQUEUE
echo ""

echo "=== OPSTAGE=1 ==="
export GGML_HEXAGON_OPSTAGE=1
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
unset GGML_HEXAGON_OPSTAGE
echo ""

echo "=== OPBATCH=2048+OPQUEUE=32 ==="
export GGML_HEXAGON_OPBATCH=2048
export GGML_HEXAGON_OPQUEUE=32
timeout 120 $BENCH --plugin llama_cpp --device npu -m $MODEL -n 8 -p 32 -t 8 2>&1 | grep -E "\[ok\]|ABORT|failed|decode_speed"
echo ""

echo "=== DONE ==="
