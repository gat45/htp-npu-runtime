#!/system/bin/sh
echo "=== MNT ==="
mount | grep -i trace
echo "=== LS events ==="
ls -la /sys/kernel/tracing/events/fastrpc/enable 2>&1
ls -la /sys/kernel/debug/tracing/events/fastrpc/enable 2>&1
echo "=== TEST WRITE ==="
echo 1 > /sys/kernel/tracing/events/fastrpc/fastrpc_dma_map/enable 2>&1 && echo WRITE_OK
echo "=== whoami ==="
id
