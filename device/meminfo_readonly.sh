echo '=== MEMINFO ==='
grep -E 'MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|Cached:|Shmem:' /proc/meminfo
echo '=== SWAP/zRAM ==='
cat /proc/swaps
cat /sys/block/zram0/disksize 2>/dev/null
echo '=== DMA HEAPS ==='
ls -la /dev/dma_heap/ 2>/dev/null
echo '=== FASTRPC ==='
ls /dev/ | grep -E 'fast|dsp'
echo '=== PARTITIONS by-name ==='
ls -la /dev/block/by-name/ 2>/dev/null | head -60