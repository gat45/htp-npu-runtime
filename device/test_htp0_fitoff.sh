#!/system/bin/sh
# Test decisif : HTP0 seul, fit off, ubatch 16 (contourne OpenCL + get_memory)
export LD_LIBRARY_PATH=/data/local/tmp/npu:/vendor/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3200
export GGML_SCHED_DEBUG=2

pkill -f llama-server 2>/dev/null
sleep 2

cd /data/local/tmp/npu
./bin/llama-server \
    -m /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf \
    -ngl 99 \
    -dev HTP0 \
    --fit off \
    -c 2048 \
    -ub 16 \
    -fa on \
    --no-mmap \
    -t 6 \
    --host 127.0.0.1 --port 18181
