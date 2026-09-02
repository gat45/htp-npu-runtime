#!/system/bin/sh
TR=/sys/kernel/tracing
echo "=== context_free ==="
cat "$TR/events/fastrpc/fastrpc_context_free/format" | grep field:
echo "=== msg ==="
cat "$TR/events/fastrpc/fastrpc_msg/format" | grep field:
echo "=== perf_counters ==="
cat "$TR/events/fastrpc/fastrpc_perf_counters/format" | grep field:
echo "=== dspsignal ==="
cat "$TR/events/fastrpc/fastrpc_dspsignal/format" | grep field:
echo "=== context_interrupt ==="
cat "$TR/events/fastrpc/fastrpc_context_interrupt/format" | grep field:
