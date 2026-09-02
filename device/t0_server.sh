#!/system/bin/sh
# T0 baseline — lance llama-server JZ (md5 1568cb07) sur le 9B Q4_0
cd /data/local/tmp/jz
export LD_LIBRARY_PATH=/data/local/tmp/jz/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/jz/lib
export CDSP_LIBRARY_PATH=/data/local/tmp/jz/lib
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3000
export GGML_HEXAGON_VERBOSE=1
exec ./bin/llama-server \
  -m /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf \
  -c 2048 -ngl 60 --no-mmap \
  --host 0.0.0.0 --port 18181 -t 6 -lv 3
