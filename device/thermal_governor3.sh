#!/system/bin/sh
# Thermal governor v3: monitor ALL hot zones EXCEPT trip points, switch at 60C.
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

MODEL="${1:-/data/local/tmp/Qwen3.5-9B-D2-A.gguf}"
THRESH=60

read_max_temp() {
  local best=0
  for z in /sys/class/thermal/thermal_zone*; do
    local t=$(cat "$z/type" 2>/dev/null)
    # skip trip points (fixed thresholds, not real temps)
    case "$t" in
      *trip*) continue ;;
    esac
    case "$t" in
      gpuss*|gpu*|cpu*|cluster*|soc*|ddr*|tsens*)
        local v=$(cat "$z/temp" 2>/dev/null)
        [ -n "$v" ] && [ "$v" -gt "$best" ] && best=$v
        ;;
    esac
  done
  echo $((best/1000))
}

echo "=== Gov3 SHORT start, real_temp=$(read_max_temp)C ==="

./llama-bench -m "$MODEL" -ngl 99 -p 4 -n 4 -t 8 -sm layer -dev GPUOpenCL,HTP0 -ts 0.8,0.2 \
  > /data/local/tmp/gov3_gpu.log 2>&1
echo "GPU run done. Max real temp: $(read_max_temp)C"

T=$(read_max_temp)
echo "max_real_temp=${T}C"
if [ "$T" -ge "$THRESH" ]; then
  echo "Temp ${T}C >= ${THRESH}C -> switch to NPU"
  ./llama-bench -m "$MODEL" -ngl 99 -p 4 -n 4 -t 8 -sm layer -dev HTP0,GPUOpenCL -ts 0.8,0.2 \
    > /data/local/tmp/gov3_npu.log 2>&1
  echo "NPU run done. Max real temp: $(read_max_temp)C"
else
  echo "Temp OK, no switch"
fi
echo "=== Gov3 done ==="