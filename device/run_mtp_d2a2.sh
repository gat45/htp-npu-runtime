#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

# Test MTP on corrected D2-A-MTP
./llama-cli --spec-type draft-mtp -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf -p "The capital of France is" -n 32 -ngl 99 -t 8 \
  > /data/local/tmp/mtp_d2amtp2.log 2>&1
echo "MTP_DONE"