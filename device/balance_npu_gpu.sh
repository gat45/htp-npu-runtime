#!/system/bin/sh
# Balance work between NPU (HTP0) and GPU (OpenCL) when hot/saturated.
# For D2-A: NPU does work but no temp exposed -> use fastrpc dmesg count as NPU activity proxy.
# GPU has temp (gpuss) -> switch to NPU when GPU hot, switch to GPU when NPU saturated.
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

M=/data/local/tmp/Qwen3.5-9B-D2-A.gguf
GPU_HOT=60          # switch to NPU if GPU above this
NPU_SAT_DELTA=50    # switch to GPU if fastrpc dmesg delta >= this (NPU saturated)

read_gpu_temp() {
  local best=0
  for z in /sys/class/thermal/thermal_zone*; do
    local t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      gpuss*) local v=$(cat "$z/temp" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$best" ] && best=$v ;;
    esac
  done
  echo $((best/1000))
}

read_fastrpc() {
  dmesg 2>/dev/null | grep -ci 'fastrpc' || echo 0
}

echo "=== BALANCE NPU/GPU start, gpu_temp=$(read_gpu_temp)C ==="
BACKEND="HTP0"
for i in 1 2 3 4 5 6; do
  # Run one benchmark on current backend
  if [ "$BACKEND" = "HTP0" ]; then
    ./llama-bench -m $M -ngl 99 -p 16 -n 8 -t 8 -dev HTP0 > /data/local/tmp/bal_npu.log 2>&1
    F0=$(read_fastrpc); sleep 1; F1=$(read_fastrpc)
    echo "RUN$i NPU done. fastrpc_delta=$((F1-F0)) gpu_temp=$(read_gpu_temp)C"
    # Check if NPU saturated (high fastrpc activity) -> switch to GPU
    if [ $((F1-F0)) -ge $NPU_SAT_DELTA ]; then
      echo "  NPU saturated (delta $((F1-F0))) -> switch to GPU"
      BACKEND="GPUOpenCL"
    fi
  else
    ./llama-bench -m $M -ngl 99 -p 16 -n 8 -t 8 -dev GPUOpenCL > /data/local/tmp/bal_gpu.log 2>&1
    T=$(read_gpu_temp)
    echo "RUN$i GPU done. gpu_temp=${T}C"
    # If GPU hot -> switch to NPU
    if [ "$T" -ge "$GPU_HOT" ]; then
      echo "  GPU ${T}C >= ${GPU_HOT}C -> switch to NPU"
      BACKEND="HTP0"
    fi
  fi
done
echo "=== BALANCE done, final backend=$BACKEND ==="