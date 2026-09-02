#!/system/bin/sh
echo 1 > /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/enable 2>/dev/null
echo 1 > /sys/kernel/tracing/events/dcvs/bw_hwmon_update/enable 2>/dev/null
echo 1 > /sys/kernel/tracing/events/dcvs/memlat_dev_meas/enable 2>/dev/null
echo > /sys/kernel/tracing/trace 2>/dev/null
sleep 3
cat /sys/kernel/tracing/trace 2>/dev/null | grep -E 'bw_hwmon_(meas|update)|memlat_dev_meas' | grep -E 'ddr|memlat' | head -20
echo 0 > /sys/kernel/tracing/events/dcvs/bw_hwmon_meas/enable 2>/dev/null
echo 0 > /sys/kernel/tracing/events/dcvs/bw_hwmon_update/enable 2>/dev/null
echo 0 > /sys/kernel/tracing/events/dcvs/memlat_dev_meas/enable 2>/dev/null
echo '=== done ==='
