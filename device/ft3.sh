#!/system/bin/sh
TR=/sys/kernel/tracing
echo "=== EVENTS FASTRPC ==="
ls $TR/events/ | grep -i fastrpc
echo "=== CONTENU ==="
ls $TR/events/fastrpc 2>/dev/null
