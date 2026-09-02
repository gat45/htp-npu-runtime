#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs:/data/local/tmp/jz/lib
export CDSP_LIBRARY_PATH=/data/local/tmp
M8=/data/local/tmp/Qwen3-8B-Q4_K_M.gguf
echo "=== GenieX llama_cpp 8B SANS draft ==="
./geniex-bench --plugin llama_cpp --device npu -m $M8 -n 32 > /data/local/tmp/mtp_base.log 2>&1
echo "EXIT=$?"
grep -E "decode=|\[ok|Abort|error" /data/local/tmp/mtp_base.log | tail -3
echo "=== GenieX llama_cpp 8B draft-tokens 4 ==="
./geniex-bench --plugin llama_cpp --device npu -m $M8 -n 32 --draft-tokens 4 --draft-min 1 > /data/local/tmp/mtp_draft.log 2>&1
echo "EXIT=$?"
grep -E "decode=|\[ok|draft|accept|Abort|error" /data/local/tmp/mtp_draft.log | tail -6