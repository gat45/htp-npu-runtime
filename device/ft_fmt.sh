#!/system/bin/sh
TR=/sys/kernel/tracing
echo "=== dma_alloc ==="
cat "$TR/events/fastrpc/fastrpc_dma_alloc/format" 2>/dev/null
echo "=== dma_map ==="
cat "$TR/events/fastrpc/fastrpc_dma_map/format" 2>/dev/null
echo "=== dma_unmap ==="
cat "$TR/events/fastrpc/fastrpc_dma_unmap/format" 2>/dev/null
echo "=== dma_free ==="
cat "$TR/events/fastrpc/fastrpc_dma_free/format" 2>/dev/null
echo "=== context_alloc ==="
cat "$TR/events/fastrpc/fastrpc_context_alloc/format" 2>/dev/null
echo "=== context_complete ==="
cat "$TR/events/fastrpc/fastrpc_context_complete/format" 2>/dev/null
echo "=== transport_send ==="
cat "$TR/events/fastrpc/fastrpc_transport_send/format" 2>/dev/null
echo "=== transport_response ==="
cat "$TR/events/fastrpc/fastrpc_transport_response/format" 2>/dev/null
