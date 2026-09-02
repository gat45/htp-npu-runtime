#!/system/bin/sh
TR=/sys/kernel/tracing
OUT=/data/local/tmp/infer_trace.txt
echo 0 > "$TR/tracing_on"
echo > "$TR/trace"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_alloc/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_map/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_unmap/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_free/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_alloc/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_complete/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_transport_send/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_transport_response/enable"
echo 1 > "$TR/tracing_on"
echo "TRACE ON $(date +%T)"
input tap 636 2441
sleep 1
input text "Hello"
sleep 1
input tap 636 2632
echo "SENT $(date +%T)"
sleep 30
echo 0 > "$TR/tracing_on"
cat "$TR/trace" > "$OUT"
echo "=== SAVED: $OUT ==="
wc -l "$OUT"
echo "=== FASTRPC EVENTS ==="
grep -c "fastrpc_" "$OUT"
echo "=== CONTEXT + DMA + TRANSPORT (derniers 60) ==="
grep -E "fastrpc_(dma_alloc|dma_map|dma_unmap|dma_free|context_alloc|context_complete|transport_send|transport_response):" "$OUT" | tail -60
echo "=== RESPONSES != 0 ==="
grep "fastrpc_transport_response:" "$OUT" | grep -v "retval 0x0" | head
echo "=== MAX DMA MAP ==="
grep "fastrpc_dma_map:" "$OUT" | grep -oE "size [0-9]+ \(len [0-9]+\)" | sort -t' ' -k2 -rn | head -5
