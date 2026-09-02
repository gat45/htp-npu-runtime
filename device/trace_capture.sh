#!/system/bin/sh
TR=/sys/kernel/tracing
EV=$TR/events/fastrpc
echo 0 > $TR/tracing_on
echo nop > $TR/current_tracer
echo 0 > $EV/enable 2>/dev/null
# activer chaque event individuellement
for e in fastrpc_dma_alloc fastrpc_dma_map fastrpc_dma_unmap fastrpc_dma_free fastrpc_context_alloc fastrpc_context_complete fastrpc_context_free fastrpc_transport_send fastrpc_transport_response fastrpc_dspsignal fastrpc_perf_counters; do
  echo 1 > $EV/$e/enable 2>/dev/null
done
echo 1 > $EV/enable 2>/dev/null
echo 16384 > $TR/buffer_size_kb 2>/dev/null
echo "RECORDER_PID=$$"
# Forcer l'arret de l'app puis relancer l'activite
am force-stop com.op15.toolkit 2>/dev/null
sleep 1
echo 1 > $TR/tracing_on
echo "TRACING_ON $(date +%T)"
am start -n com.op15.toolkit/.NpuChatActivity
sleep 25
echo 0 > $TR/tracing_on
echo "=== TRACE (fastrpc, compact) ==="
grep "fastrpc" $TR/trace | sed -E 's/^ +//' | cut -c1-200 | tail -120
echo "=== STATS ==="
echo "dma_map count:"; grep -c "fastrpc_dma_map:" $TR/trace
echo "dma_alloc count:"; grep -c "fastrpc_dma_alloc:" $TR/trace
echo "transport_send count:"; grep -c "fastrpc_transport_send:" $TR/trace
echo "transport_response count:"; grep -c "fastrpc_transport_response:" $TR/trace
echo "=== RESPONSES RETVAL != 0 ==="
grep "fastrpc_transport_response" $TR/trace | grep -v "retval 0x0" | head -20
echo "=== MAX DMA MAP SIZES ==="
grep "fastrpc_dma_map:" $TR/trace | grep -oE "size [0-9]+ \(len [0-9]+\)" | sort -t' ' -k2 -rn | head -10
echo 0 > $EV/enable 2>/dev/null
cp $TR/trace /data/local/tmp/fastrpc_trace.txt 2>/dev/null
echo "SAVED /data/local/tmp/fastrpc_trace.txt"
