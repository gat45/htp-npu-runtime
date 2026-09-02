#!/system/bin/sh
TR=/sys/kernel/tracing
OUT=/data/local/tmp/ui_infer_trace.txt
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
uiautomator dump /data/local/tmp/uic.xml 2>&1
ET=$(grep -oE 'etInput[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/uic.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
SEND=$(grep -oE 'btnSend[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/uic.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "ET=$ET SEND=$SEND"
input tap 636 2441
sleep 1
input text "hello"
sleep 1
input keyevent 4
sleep 1
input tap 636 2632
echo "SENT $(date +%T)"
sleep 25
echo 0 > "$TR/tracing_on"
cat "$TR/trace" > "$OUT"
echo "=== TRACE LINES: $(wc -l < $OUT) ==="
echo "=== FASTRPC EVENTS: $(grep -c 'fastrpc_' $OUT) ==="
grep -E "fastrpc_(dma_alloc|dma_map|dma_unmap|dma_free|context_alloc|context_complete|transport_send|transport_response):" "$OUT" | tail -50
echo "=== MAPS APRES (qnn/htp/cdsp) ==="
PID=$(pidof com.op15.toolkit)
grep -Ei "Qnn|htp|cdsp|fastrpc|hexagon|genie" /proc/$PID/maps 2>/dev/null | grep -oE "/[^ ]+\.so" | sort -u
