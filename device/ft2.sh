#!/system/bin/sh
echo "=== SYMBOLES MODULE ==="
cat /proc/kallsyms | grep -iE "fastrpc" | head -50
