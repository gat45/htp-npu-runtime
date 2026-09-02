#!/system/bin/sh
TR=/sys/kernel/tracing
echo "=== dma_alloc ==="
cat $TR/events/fastrpc/fastrpc_dma_alloc/format | grep field:
echo "=== dma_map ==="
cat $TR/events/fastrpc/fastrpc_dma_map/format | grep field:
echo "=== dma_unmap ==="
cat $TR/events/fastrpc/fastrpc_dma_unmap/format | grep field:
echo "=== context_alloc ==="
cat $TR/events/fastrpc/fastrpc_context_alloc/format | grep field:
