#!/system/bin/sh
echo "=== DEVFREQ ==="
ls /sys/class/devfreq/ 2>/dev/null
echo "=== HTP devices ==="
ls -d /sys/devices/platform/*htp* /sys/devices/platform/*cdsp* 2>/dev/null
ls -d /sys/class/devfreq/*htp* 2>/dev/null
echo "=== HTP clk ==="
for d in /sys/kernel/debug/htp /d/htp /sys/devices/platform/3d00000.htp /sys/devices/platform/1d00000.htp; do
  if [ -d "$d" ]; then echo "FOUND $d"; ls "$d" | head -20; fi
done
echo "=== power_supply ==="
ls /sys/class/power_supply/
echo "=== thermal (top) ==="
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null)
  v=$(cat "$z/temp" 2>/dev/null)
  [ -n "$t" ] && echo "$t|$v"
done | head -30
echo "=== kgsl gpu clk/load ==="
cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null
cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null
echo "=== meminfo ==="
head -5 /proc/meminfo