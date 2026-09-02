#!/system/bin/sh
# Thermal governor: monitor GPU temp, switch GPU<->NPU at 60C threshold with hysteresis.
# Usage: sh thermal_governor.sh <model> [quiet]
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

MODEL="${1:-/data/local/tmp/Qwen3.5-9B-D2-A.gguf}"
THRESH=60          # switch to NPU above 60C
HYST_LO=50         # back to GPU below 50C
QUIET="${2:-0}"

read_gpu_temp() {
  local best=0
  for z in /sys/class/thermal/thermal_zone*; do
    local t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      gpuss*)
        local v=$(cat "$z/temp" 2>/dev/null)
        [ -n "$v" ] && [ "$v" -gt "$best" ] && best=$v
        ;;
    esac
  done
  echo $((best/1000))
}

state="GPU"   # GPU or NPU
echo "=== Thermal governor start: threshold=${THRESH}C model=$MODEL ==="

# Run GPU-heavy first
./llama-bench -m "$MODEL" -ngl 99 -p 16 -n 16 -t 8 -sm layer -dev GPUOpenCL,HTP0 -ts 0.8,0.2 \
  > /data/local/tmp/gov_gpu.log 2>&1
echo "GPU run done. Temp now: $(read_gpu_temp)C"

# Monitor and switch to NPU if hot
while true; do
  T=$(read_gpu_temp)
  echo "temp=${T}C state=${state}"
  if [ "$state" = "GPU" ] && [ "$T" -ge "$THRESH" ]; then
    echo "GPU > ${THRESH}C -> switch to NPU"
    state="NPU"
    ./llama-bench -m "$MODEL" -ngl 99 -p 16 -n 16 -t 8 -sm layer -dev HTP0,GPUOpenCL -ts 0.8,0.2 \
      > /data/local/tmp/gov_npu.log 2>&1
    echo "NPU run done. Temp now: $(read_gpu_temp)C"
  elif [ "$state" = "NPU" ] && [ "$T" -le "$HYST_LO" ]; then
    echo "GPU < ${HYST_LO}C -> back to GPU"
    state="GPU"
    ./llama-bench -m "$MODEL" -ngl 99 -p 16 -n 16 -t 8 -sm layer -dev GPUOpenCL,HTP0 -ts 0.8,0.2 \
      > /data/local/tmp/gov_gpu2.log 2>&1
    echo "GPU run 2 done. Temp: $(read_gpu_temp)C"
  else
    break
  fi
done
echo "=== Governor done ==="