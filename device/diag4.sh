#!/system/bin/sh
echo '=== bw_hwmon_meas format ==='
cat /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/format 2>/dev/null
echo '=== enable check ==='
echo nop > /sys/kernel/tracing/current_tracer 2>/dev/null
echo 1 > /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/enable 2>/dev/null
echo '=== reading trace_pipe 2s ==='
cat /sys/kernel/tracing/trace_pipe > /data/local/tmp/ftr.out 2>/dev/null &
FT=$!
sleep 3
kill $FT 2>/dev/null
cat /data/local/tmp/ftr.out 2>/dev/null | head -30
echo '=== disable ==='
echo 0 > /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/enable 2>/dev/null
echo '=== dmesg fastrpc ==='
dmesg 2>/dev/null | grep -i fastrpc | tail -5
