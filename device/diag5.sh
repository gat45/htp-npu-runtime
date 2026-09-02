#!/system/bin/sh
echo '=== bw_hwmon_update format ==='
cat /sys/kernel/tracing/events/dcvs/bw_hwmon_update/format 2>/dev/null
echo '=== memlat format ==='
cat /sys/kernel/tracing/events/dcvs/memlat_dev_meas/format 2>/dev/null
echo '=== test read bw ==='
echo 1 > /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/enable 2>/dev/null
echo > /sys/kernel/tracing/trace 2>/dev/null
sleep 2
cat /sys/kernel/tracing/trace 2>/dev/null | grep bw_hwmon_meas
echo 0 > /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/enable 2>/dev/null
echo '=== done ==='
