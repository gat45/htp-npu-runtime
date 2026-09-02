#!/system/bin/sh
# Thermal governor v2 short: monitor ALL zones, switch at 60C. Short bench.
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
    case "$t" in
      gpuss*|gpu*|cpu*|cluster*|soc*|ddr*|tsens*)
        local v=$(cat "$z/temp" 2>/dev/null)
        [ -n "$v" ] && [ "$v" -gt "$best" ] && best=$v
        ;;
    esac
  done
  echo $((best/1000))
}

echo "=== Gov2 SHORT start, start_temp=$(read_max_temp)C ==="

# GPU-heavy short run (20% HTP front, 80% GPU back)
./llama-bench -m "$MODEL" -ngl 99 -p 4 -n 4 -t 8 -sm layer -dev GPUOpenCL,HTP0 -ts 0.8,0.2 \
  > /data/local/tmp/gov2s_gpu.log 2>&1
echo "GPU run done. Max temp: $(read_max_temp)C"

# Switch to NPU if hot
T=$(read_max_temp)
echo "max_temp=${T}C"
if [ "$T" -ge "$THRESH" ]; then
  echo "Temp ${T}C >= ${THRESH}C -> switch to NPU"
  ./llama-bench -m "$MODEL" -ngl 99 -p 4 -n 4 -t 8 -sm layer -dev HTP0,GPUOpenCL -ts 0.8,0.2 \
    > /data/local/tmp/gov2s_npu.log 2>&1
  echo "NPU run done. Max temp: $(read_max_temp)C"
else
  echo "Temp OK, no switch needed"
fi
echo "=== Gov2 SHORT done ==="