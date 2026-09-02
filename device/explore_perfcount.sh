#!/system/bin/sh
# Test du load NPU via fastrpc_perf_counters + dspsignal pendant 2s
echo "=== perf_counters dispo ? ==="
ls /sys/kernel/tracing/events/fastrpc/fastrpc_perf_counters/ 2>/dev/null
echo "=== reset + capture 2s ==="
echo "0" > /sys/kernel/tracing/tracing_on 2>/dev/null
echo > /sys/kernel/tracing/trace 2>/dev/null
echo "fastrpc_perf_counters" > /sys/kernel/tracing/set_event 2>/dev/null
echo "fastrpc_dspsignal" > /sys/kernel/tracing/set_event 2>/dev/null
echo "1" > /sys/kernel/tracing/tracing_on 2>/dev/null
sleep 2
echo "0" > /sys/kernel/tracing/tracing_on 2>/dev/null
echo "=== comptes ==="
echo -n "dspsignal: "; grep -c 'fastrpc_dspsignal' /sys/kernel/tracing/trace 2>/dev/null
echo -n "perf_counters: "; grep -c 'fastrpc_perf_counters' /sys/kernel/tracing/trace 2>/dev/null
echo "=== échantillon perf_counters (payload) ==="
grep 'fastrpc_perf_counters' /sys/kernel/tracing/trace 2>/dev/null | head -3
echo "0" > /sys/kernel/tracing/set_event 2>/dev/null
echo "=== try load NPU via existing libs (qairt probe si possible) ==="
ls /data/local/tmp/gxlibs/ 2>/dev/null | head
ls /vendor/lib64/libQnnHtp*.so 2>/dev/null | head