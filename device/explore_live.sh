#!/system/bin/sh
echo "=== CPU (top freqs) ==="
for i in 0 4 8 12; do echo -n "cpu$i: "; cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq 2>/dev/null; done
echo "=== GPU kgsl ==="
echo -n "gpuclk: "; cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null
echo -n "gpubusy (busy total): "; cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null
echo -n "max_freq: "; cat /sys/class/kgsl/kgsl-3d0/max_gpuclk 2>/dev/null
echo -n "min: "; cat /sys/class/kgsl/kgsl-3d0/min_gpuclk 2>/dev/null
echo "=== NPU/htp via debugfs ==="
find /sys/kernel/debug -maxdepth 3 -iname '*htp*' 2>/dev/null | head
find /sys/kernel/debug -maxdepth 3 -iname '*cdsp*' 2>/dev/null | head
find /sys/kernel/debug -maxdepth 3 -iname '*fastrpc*' 2>/dev/null | head
ls /sys/kernel/debug/fastrpc 2>/dev/null
echo "=== nsp hvx threads ==="
find /sys/kernel/debug -maxdepth 3 -iname '*hvx*' 2>/dev/null | head
echo "=== thermal NPU/GPU ==="
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null); v=$(cat "$z/temp" 2>/dev/null)
  case "$t" in *nsp*|*qmx*|*gpu*|*cpullc*) echo "$t=$v";; esac
done | head -20
echo "=== battery ==="
echo -n "level: "; cat /sys/class/power_supply/battery/capacity 2>/dev/null
echo -n "current_now uA: "; cat /sys/class/power_supply/battery/current_now 2>/dev/null
echo -n "volt_now uV: "; cat /sys/class/power_supply/battery/voltage_now 2>/dev/null
echo "=== ram ==="
grep -E 'MemTotal|MemAvailable' /proc/meminfo
echo "=== lmh ==="
cat /sys/class/thermal/thermal_message/sconfig 2>/dev/null
ls /sys/class/thermal/thermal_message 2>/dev/null
echo "=== /proc/stat (cpu%) ==="
head -1 /proc/stat