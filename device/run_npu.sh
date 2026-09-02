#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu/lib:/vendor/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/npu/lib
cd /data/local/tmp/npu
exec ./bin/llama-server -m /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf --host 0.0.0.0 --port 8099 -ngl 0 -c 2048 --no-mmap
