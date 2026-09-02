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
# Saisir un message dans le champ
input tap 540 1800
sleep 1
input text "Hello"
sleep 1
echo "=== UI CHAMP ==="
uiautomator dump /data/local/tmp/ui2.xml 2>&1
grep -oE 'text="[^"]{1,40}"' /data/local/tmp/ui2.xml | grep -v "systemui" | head -10
