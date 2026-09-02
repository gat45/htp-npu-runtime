#!/system/bin/sh
cd /data/local/tmp/npu
export LD_LIBRARY_PATH=./lib
export ADSP_LIBRARY_PATH=./lib
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_HOSTBUF=1
export GGML_HEXAGON_MBUF=3200
export GGML_BACKEND_DEBUG=1
echo "=== AXE2 GGML/NPU Qwen3-8B Q4_K_M ==="
./llama-bench -m /data/local/tmp/Qwen3-8B-Q4_K_M.gguf -p 512 -n 256 -r 3 -ngl 99 -fa 1 --device HTP0 2>&1
echo "=== END ==="
