#!/system/bin/sh
TR=/sys/kernel/tracing
OUT=/data/local/tmp/app_load_trace.txt
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
echo 1 > "$TR/tracing_on"
echo "TRACE ON $(date +%T)"
am force-stop com.op15.toolkit
sleep 1
am start -n com.op15.toolkit/.NpuChatActivity
echo "App started, waiting 60s (model load via UI)"
sleep 60
echo 0 > "$TR/tracing_on"
cat "$TR/trace" > "$OUT"
echo "=== SAVED: $OUT ==="
wc -l "$OUT"
echo "=== FASTRPC EVENTS ==="
grep -c "fastrpc_" "$OUT"
echo "=== DMA MAP (size/phys) ==="
grep "fastrpc_dma_map:" "$OUT" | grep -oE "cid [0-9-]+, fd [0-9]+, phys 0x[0-9a-f]+, size [0-9]+ \(len [0-9]+\)" | sort -t' ' -k5 -rn | head -20
echo "=== TRANSPORT RESPONSES (erreurs) ==="
grep "fastrpc_transport_response:" "$OUT" | grep -v "retval 0x0" | head -10
