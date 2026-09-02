#!/system/bin/sh
TR=/sys/kernel/tracing
echo "=== FONCTIONS DU MODULE ==="
grep -iE "fastrpc|frpc" $TR/available_filter_functions | head -40
echo "=== TRACERS ==="
cat $TR/available_tracers
echo "=== CURRENT ==="
cat $TR/current_tracer
