#!/system/bin/sh
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/qz:/data/local/tmp/bench/lib
./llama-quantize /data/local/tmp/Qwen3-8B-Q4_K_M.gguf /data/local/tmp/Qwen3-8B-Q4_0.gguf Q4_0 > /data/local/tmp/quant2.log 2>&1
echo "EXIT=$?"
tail -3 /data/local/tmp/quant2.log
ls -la /data/local/tmp/Qwen3-8B-Q4_0.gguf 2>/dev/null