#!/system/bin/sh
echo "=== ZONEINFO ==="
grep -E "^Node|pages free|pages_cma" /proc/zoneinfo | head -40
echo "=== BUDDYINFO ==="
head -8 /proc/buddyinfo
echo "=== CMA ==="
grep -E "CmaTotal|CmaFree" /proc/meminfo
echo "=== DMESG FAST ==="
dmesg | grep -iE "cma|fastrpc|dma-heap" | tail -20
echo "=== DEBUGFS ==="
ls /sys/kernel/debug 2>/dev/null | head
