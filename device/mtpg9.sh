#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs:/data/local/tmp/jz/lib
export CDSP_LIBRARY_PATH=/data/local/tmp
M9=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
echo "=== GenieX llama_cpp 9B Q4_0 sans draft ==="
./geniex-bench --plugin llama_cpp --device npu -m $M9 -n 32 > /data/local/tmp/m9b.log 2>&1
echo "EXIT=$?"
grep -E "decode=|\[ok|Abort" /data/local/tmp/m9b.log | tail -3
echo "=== GenieX llama_cpp 9B Q4_0 draft-tokens 4 ==="
./geniex-bench --plugin llama_cpp --device npu -m $M9 -n 32 --draft-tokens 4 --draft-min 1 > /data/local/tmp/m9d.log 2>&1
echo "EXIT=$?"
grep -E "decode=|\[ok|draft|accept|Abort" /data/local/tmp/m9d.log | tail -6