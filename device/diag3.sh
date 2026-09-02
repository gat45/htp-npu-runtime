#!/system/bin/sh
echo '=== bwmon-ddr ==='
ls /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/
echo '--- files ---'
cat /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/cur_freq 2>/dev/null
cat /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/freq_histogram 2>/dev/null
cat /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/hw_bw 2>/dev/null
cat /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/meas_bw 2>/dev/null
cat /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/bw_scale 2>/dev/null
cat /sys/devices/platform/soc/31091000.qcom,bwmon-ddr/sample_ms 2>/dev/null
echo '=== llcc-gold ==='
ls /sys/devices/platform/soc/310b3400.qcom,bwmon-llcc-gold/ 2>/dev/null
cat /sys/devices/platform/soc/310b3400.qcom,bwmon-llcc-gold/cur_freq 2>/dev/null
cat /sys/devices/platform/soc/310b3400.qcom,bwmon-llcc-gold/hw_bw 2>/dev/null
cat /sys/devices/platform/soc/310b3400.qcom,bwmon-llcc-gold/meas_bw 2>/dev/null
echo '=== llcc-prime ==='
ls /sys/devices/platform/soc/310b7400.qcom,bwmon-llcc-prime/ 2>/dev/null
cat /sys/devices/platform/soc/310b7400.qcom,bwmon-llcc-prime/cur_freq 2>/dev/null
cat /sys/devices/platform/soc/310b7400.qcom,bwmon-llcc-prime/hw_bw 2>/dev/null
cat /sys/devices/platform/soc/310b7400.qcom,bwmon-llcc-prime/meas_bw 2>/dev/null
echo '=== devfreq ==='
ls /sys/class/devfreq/ 2>/dev/null
echo '=== tracing events dcvs ==='
ls /sys/kernel/tracing/events/ 2>/dev/null | head -40
ls /sys/kernel/tracing/events/dcvs/ 2>/dev/null
