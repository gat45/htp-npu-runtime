#!/system/bin/sh
echo "=== FTRACE ==="
ls /sys/kernel/tracing 2>/dev/null | head -5
ls /sys/kernel/debug/tracing 2>/dev/null | head -5
echo "=== KPROBE ==="
ls /sys/kernel/tracing/kprobe_events 2>/dev/null
ls /sys/kernel/debug/tracing/kprobe_events 2>/dev/null
echo "=== AVAILABLE FILTERS ==="
cat /sys/kernel/tracing/available_filter_functions 2>/dev/null | grep -i fastrpc | head
cat /sys/kernel/debug/tracing/available_filter_functions 2>/dev/null | grep -i fastrpc | head
echo "=== MODULES CHARGES ==="
lsmod | grep -iE 'fastrpc|adsprpc|cdsp'
