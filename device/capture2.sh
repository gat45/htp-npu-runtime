#!/system/bin/sh
TR=/sys/kernel/tracing
OUT=/data/local/tmp/fastrpc_capture.txt
echo 0 > "$TR/tracing_on"
echo > "$TR/trace"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_alloc/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_map/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_unmap/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_free/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_alloc/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_complete/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_free/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_transport_send/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_transport_response/enable"
echo "=== VERIFY ENABLED ==="
for e in fastrpc_dma_alloc fastrpc_dma_map fastrpc_dma_unmap fastrpc_dma_free fastrpc_context_alloc fastrpc_transport_send fastrpc_transport_response; do
  printf "%s=" "$e"; cat "$TR/events/fastrpc/$e/enable"
done
echo 1 > "$TR/tracing_on"
echo "TRACING_ON $(date +%T)"
am force-stop com.op15.toolkit 2>/dev/null
sleep 1
am start -n com.op15.toolkit/.NpuChatActivity
echo "APP STARTED, sleeping 40s"
sleep 40
echo 0 > "$TR/tracing_on"
cat "$TR/trace" > "$OUT"
echo "=== SAVED: $OUT ==="
wc -l "$OUT"
echo "=== FASTRPC EVENTS ==="
grep -c "fastrpc_" "$OUT"
grep "fastrpc_" "$OUT" | tail -40
