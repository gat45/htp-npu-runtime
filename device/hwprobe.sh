#!/system/bin/sh
echo "=== CPU freqs ==="
for c in 0 1 2 3 4 5 6 7; do
  f=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null)
  g=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null)
  echo "cpu$c: ${f}kHz / ${g}"
done
echo "=== THERMAL ==="
for z in 0 1 2 3 4 5 6 7 8; do
  t=$(cat /sys/class/thermal/thermal_zone$z/temp 2>/dev/null)
  ty=$(cat /sys/class/thermal/thermal_zone$z/type 2>/dev/null)
  echo "$ty: $t"
done
echo "=== MEM ==="
grep -E "MemTotal|MemFree|Buffers|Cached" /proc/meminfo
echo "gpu_mem_total: $(cat /sys/class/kgsl/kgsl-3d0/gpu_mem_total 2>/dev/null)"
echo "=== GPU clk ==="
cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || cat /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
echo "=== VMEM/HEXAGON ==="
ls /sys/kernel/debug/fastrpc 2>/dev/null; cat /proc/interrupts 2>/dev/null | grep -i fastrpc | head -3
echo "=== DDR clk ==="
for d in $(ls /sys/kernel/debug/clk 2>/dev/null | grep -iE "ddr|dram" | head -5); do echo "$d: $(cat /sys/kernel/debug/clk/$d/clk_rate 2>/dev/null)"; done
