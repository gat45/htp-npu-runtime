#!/system/bin/sh
TR=/sys/kernel/tracing
for e in fastrpc_dma_alloc fastrpc_dma_map fastrpc_dma_unmap fastrpc_dma_free fastrpc_context_alloc fastrpc_transport_send; do
  echo "=== $e ==="
  cat $TR/events/fastrpc/$e/format 2>/dev/null | grep -E "field:" | head -12
done
