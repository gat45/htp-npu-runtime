#!/system/bin/sh
M=/vendor/lib/modules/frpc-adsprpc.ko
echo "find_vma: $(grep -ac 'find_vma' $M 2>/dev/null)"
echo "vma_lookup: $(grep -ac 'vma_lookup' $M 2>/dev/null)"
echo "dma_buf_get: $(grep -ac 'dma_buf_get' $M 2>/dev/null)"
echo "dma_buf_put: $(grep -ac 'dma_buf_put' $M 2>/dev/null)"
echo "fastrpc_get_args: $(grep -ac 'fastrpc_get_args' $M 2>/dev/null)"
