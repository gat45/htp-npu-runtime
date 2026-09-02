#!/system/bin/sh
echo "=== KALLSYMS frpc (find_vma/vma_lookup/dma_buf) ==="
grep -E "find_vma|vma_lookup|dma_buf_get|dma_buf_put|fastrpc_get_args" /proc/kallsyms 2>/dev/null | grep -iE "frpc|fastrpc" | head -20
echo "=== TOUS find_vma/vma_lookup ==="
grep -cE "find_vma" /proc/kallsyms 2>/dev/null
grep -cE "vma_lookup" /proc/kallsyms 2>/dev/null
echo "=== STRINGS MODULE ==="
strings /vendor/lib/modules/frpc-adsprpc.ko 2>/dev/null | grep -iE "find_vma|vma_lookup|dma_buf" | head
