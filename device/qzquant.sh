#!/system/bin/sh
echo "=== quantize 8B Q4_K_M -> Q4_0 via qz pile ==="
cd /data/local/tmp/qz
export LD_LIBRARY_PATH=/data/local/tmp/qz
./llama-quantize /data/local/tmp/Qwen3-8B-Q4_K_M.gguf /data/local/tmp/Qwen3-8B-Q4_0.gguf Q4_0 > /data/local/tmp/qz_quant.log 2>&1
echo "EXIT=$?"
tail -3 /data/local/tmp/qz_quant.log
ls -la /data/local/tmp/Qwen3-8B-Q4_0.gguf 2>/dev/null