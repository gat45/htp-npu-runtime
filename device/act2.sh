#!/system/bin/sh
# Action 2 — strict same-model : Qwen3-8B Q4_K_M -> Q4_0 (GGML) vs w4a16 (QAIRT)
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/bench/lib
echo "=== quantize 8B Q4_K_M -> Q4_0 ==="
./llama-quantize /data/local/tmp/Qwen3-8B-Q4_K_M.gguf /data/local/tmp/Qwen3-8B-Q4_0.gguf Q4_0 2>&1 | tail -3
ls -la /data/local/tmp/Qwen3-8B-Q4_0.gguf
echo "EXIT=$?"