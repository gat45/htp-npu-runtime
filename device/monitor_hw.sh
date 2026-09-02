#!/system/bin/sh
# Monitor GPU/NPU utilization + temperature
echo "=== TEMPERATURES ==="
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat $z/type 2>/dev/null)
  v=$(cat $z/temp 2>/dev/null)
  if [ -n "$t" ] && [ -n "$v" ]; then
    echo "$t: $((v/1000))C"
  fi
done | sort -t: -k2 -rn | head -10

echo "=== GPU UTILIZATION ==="
cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null || cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null || echo "NO_GPU_BUSY"
cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || echo "NO_GPUCLK"

echo "=== CPU LOAD ==="
cat /proc/loadavg