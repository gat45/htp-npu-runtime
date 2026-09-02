#!/system/bin/sh
# Sonde governor — validation des sources de données (root)
echo "===KGSL==="
ls /sys/class/kgsl/kgsl-3d0/ 2>/dev/null | grep -E "busy|clk|mem|percent" | head -10
cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null
cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null
echo "===DEBUGFS==="
grep debugfs /proc/mounts | head -2 || echo "debugfs non monté"
[ -d /d/kgsl ] && ls /d/kgsl/kgsl-3d0 2>/dev/null | head -5
echo "===SMAPS-TOOLKIT==="
P=$(pidof com.op15.toolkit)
[ -n "$P" ] && head -14 /proc/$P/smaps_rollup 2>/dev/null || echo "smaps KO"
echo "===ENVIRON-TOOLKIT==="
[ -n "$P" ] && cat /proc/$P/environ 2>/dev/null | tr '\0' '\n' | wc -l
echo "===STAT-PID1==="
head -1 /proc/stat
echo "===PERF-TEST==="
which perf 2>/dev/null || echo "perf binaire absent (perf_event_open via code natif alors)"
