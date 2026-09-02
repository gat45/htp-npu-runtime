#!/system/bin/sh
echo '=== CPU freq ==='
for c in 0 1 2 3 4 5 6 7; do
  printf 'cpu%s: ' "$c"
  cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null
done
echo '=== GPU ==='
cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null
cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null
cat /sys/class/kgsl/kgsl-3d0/gpu_available_frequencies 2>/dev/null
echo '=== THERMAL ==='
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null)
  v=$(cat "$z/temp" 2>/dev/null)
  echo "$z: type=$t temp=$v"
done
echo '=== DDR/LLCC ==='
ls /sys/kernel/debug 2>/dev/null | head -20
ls /sys/kernel/debug/bw_hwmon 2>/dev/null
find /sys/devices/platform -name '*bwmon*' -maxdepth 3 2>/dev/null
echo '=== remoteproc ==='
for r in /sys/class/remoteproc/remoteproc*; do
  echo "$(basename "$r"): name=$(cat "$r/name" 2>/dev/null) state=$(cat "$r/state" 2>/dev/null)"
done
echo '=== fastrpc ==='
ls -la /dev/fastrpc* 2>/dev/null
echo '=== lmh ==='
for d in /sys/kernel/lmh_stats_*; do
  echo "$d: limit=$(cat "$d/dcvsh_freq_limit" 2>/dev/null) resid=$(cat "$d/dcvsh_freq_limit_residency" 2>/dev/null)"
done
echo '=== tracing ==='
ls /sys/kernel/tracing 2>/dev/null | head -20
echo '=== modules ==='
ls /data/adb/modules 2>/dev/null
echo '=== verified boot ==='
getprop ro.boot.verifiedbootstate 2>/dev/null
getprop ro.boot.vbmeta.device_state 2>/dev/null
getprop ro.boot.warranty_bit 2>/dev/null
getprop ro.boot.flash.locked 2>/dev/null
echo '=== battery ==='
grep -E 'POWER_SUPPLY_CAPACITY|POWER_SUPPLY_TEMP|POWER_SUPPLY_STATUS' /sys/class/power_supply/battery/uevent 2>/dev/null
