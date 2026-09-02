#!/system/bin/sh
echo "=== quantize via bench/lib_cpu (CPU-only, pas de HTP requis) ==="
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/bench/lib_cpu
./llama-quantize /data/local/tmp/Qwen3-8B-Q4_K_M.gguf /data/local/tmp/Qwen3-8B-Q4_0.gguf Q4_0 2>&1 | tail -4
ls -la /data/local/tmp/Qwen3-8B-Q4_0.gguf 2>/dev/null
echo "EXIT=$?"