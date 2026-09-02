#!/system/bin/sh
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/qz:/data/local/tmp/bench/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/qz:/data/local/tmp/jz/lib
export CDSP_LIBRARY_PATH=/data/local/tmp/qz:/data/local/tmp/jz/lib
export GGML_HEXAGON_NDEV=1
./llama-quantize /data/local/tmp/Qwen3-8B-Q4_K_M.gguf /data/local/tmp/Qwen3-8B-Q4_0.gguf Q4_0 > /data/local/tmp/quant3.log 2>&1
echo "EXIT=$?"
tail -3 /data/local/tmp/quant3.log
ls -la /data/local/tmp/Qwen3-8B-Q4_0.gguf 2>/dev/null