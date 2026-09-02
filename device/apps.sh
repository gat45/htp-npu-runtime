#!/system/bin/sh
echo "=== APPS INSTALLEES ==="
pm list packages 2>/dev/null | grep -iE "op15|toolkit|scout"
echo "=== PORTS (tous) ==="
cat /proc/net/tcp 2>/dev/null | awk '{print $2}' | grep -v local | grep -v "00000000:0000" | head -20
echo "=== GENIEX SERVER ? ==="
ss -tlnp 2>/dev/null | head -20
