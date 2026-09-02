echo '=== REMOTEPROC ==='
grep -H . /sys/class/remoteproc/remoteproc*/name 2>/dev/null
grep -H . /sys/class/remoteproc/remoteproc*/state 2>/dev/null
echo '=== CMA ==='
dmesg | grep -iE 'CMA:|reserved [0-9]+ MiB' | head -8
echo '=== CDSP/VTCM devicetree ==='
find /proc/device-tree -name '*vtcm*' 2>/dev/null | head -3
find /proc/device-tree -name '*cdsp*' -maxdepth 3 2>/dev/null | head -5
echo '=== DDR freq ==='
cat /sys/class/devfreq/*ddr*/cur_freq 2>/dev/null
echo '=== NPU NSP ==='
ls /sys/class/remoteproc/ 2>/dev/null