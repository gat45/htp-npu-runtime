#!/system/bin/sh
echo "=== CHERCHE frpc-adsprpc.ko ==="
find / -name "frpc-adsprpc.ko" 2>/dev/null | head -3
echo "=== /vendor/lib/modules ==="
ls /vendor/lib/modules/frpc-adsprpc.ko 2>/dev/null
echo "=== /proc/modules ==="
grep frpc /proc/modules
echo "=== MODULE PATH (sysfs) ==="
ls -la /sys/module/frpc_adsprpc/ 2>/dev/null | head -3
cat /sys/module/frpc_adsprpc/coresize 2>/dev/null
