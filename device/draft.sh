#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
B=/data/local/tmp/qwen3-8b-w4a16
echo "=== QAIRT sans draft ==="
./geniex-bench --plugin qairt --device npu -m $B -n 32 2>&1 | grep -E "decode=" | tail -1
echo "=== QAIRT draft-tokens 4 ==="
./geniex-bench --plugin qairt --device npu -m $B -n 32 --draft-tokens 4 2>&1 | grep -E "decode=|draft" | tail -3
echo "=== llama_cpp plugin 8B Q4_K_M (meme bench) ==="
./geniex-bench --plugin llama_cpp --device npu -m /data/local/tmp/Qwen3-8B-Q4_K_M.gguf -n 32 2>&1 | grep -E "decode=|\[ok" | tail -2