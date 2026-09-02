#!/system/bin/sh
echo "=== 1. debugfs root ? ==="
cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
ls /sys/kernel/debug 2>/dev/null | head
echo "=== 2. perf/cpufreq CDSP ==="
find /sys/devices -maxdepth 4 -iname '*cdsp*' 2>/dev/null | head
find /sys/devices -maxdepth 4 -iname '*nsp*' -type d 2>/dev/null | head
echo "=== 3. devfreq ==="
find /sys/class/devfreq -maxdepth 1 2>/dev/null
for d in /sys/class/devfreq/*/; do
  n=$(basename "$d")
  echo "$n: cur=$(cat $d/cur_freq 2>/dev/null) avail=$(cat $d/available_frequencies 2>/dev/null | tr '\n' ',')"
done
echo "=== 4. qcom smem / stats NPU ==="
find /sys -maxdepth 5 -iname '*dsp*' -o -iname '*htp*' 2>/dev/null | grep -v thermal | head -20
echo "=== 5. clk framework CDSP ==="
find /sys/kernel/debug/clk -maxdepth 1 2>/dev/null | grep -iE 'cdsp|nsp|htp|npu' | head
echo "=== 6. memstat fastrpc ==="
cat /sys/kernel/debug/fastrpc/memstat 2>/dev/null | head -30
ls /sys/kernel/debug/fastrpc/ 2>/dev/null
echo "=== 7. /proc/interrupts CDSP ==="
grep -iE 'cdsp|nsp|htp|adsp' /proc/interrupts 2>/dev/null | head
echo "=== 8. hvx / nsp freq via qcom npu ==="
find /sys -maxdepth 6 -iname '*npu*' 2>/dev/null | grep -v thermal | head -20
echo "=== 9. dmesg cdsp clk ==="
dmesg 2>/dev/null | grep -iE 'cdsp|npu_clk|htp' | tail -10