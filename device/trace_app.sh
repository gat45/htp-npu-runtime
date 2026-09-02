#!/system/bin/sh
TR=/sys/kernel/tracing
mount -t tracefs tracefs $TR 2>/dev/null
echo nop > $TR/current_tracer
echo 1 > $TR/events/fastrpc/enable
echo 0 > $TR/tracing_on
echo 8192 > $TR/buffer_size_kb
echo 1 > $TR/tracing_on
echo "TRACING ON $(date +%T)"
# Lancer l'app qui charge le mod?le QAIRT
am start -n com.op15.toolkit/.NpuChatActivity 2>&1
sleep 20
# Arr?ter la trace
echo 0 > $TR/tracing_on
echo "=== TRACE FASTRPC ==="
grep -E "fastrpc" $TR/trace | grep -vE "transport_response" | tail -80
echo "=== FIN ==="
echo 0 > $TR/events/fastrpc/enable
