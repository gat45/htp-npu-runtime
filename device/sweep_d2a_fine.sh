#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

M=/data/local/tmp/Qwen3.5-9B-D2-A.gguf

for TS in "0.1,0.9" "0.2,0.8" "0.5,0.5" "0.8,0.2" "0.9,0.1"; do
  echo "=== TS=$TS ==="
  ./llama-bench -m $M -ngl 99 -p 16 -n 16 -t 8 -sm layer -dev HTP0,GPUOpenCL -ts $TS \
    >> /data/local/tmp/sweep_d2a_fine.log 2>&1
done
echo "SWEEP_FINE_DONE"