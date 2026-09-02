#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

# Test WITHOUT MTP - normal decode
./llama-bench -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf -ngl 99 -p 16 -n 16 -t 8 -dev HTP0 \
  > /data/local/tmp/bench_d2amtp_nomtp.log 2>&1
echo "NOMTP_DONE"