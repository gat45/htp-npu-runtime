#!/system/bin/sh
TR=/sys/kernel/tracing
OUT=/data/local/tmp/crash_trace.txt
echo 0 > "$TR/tracing_on"
echo > "$TR/trace"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_alloc/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_map/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_unmap/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_dma_free/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_alloc/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_complete/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_context_free/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_transport_send/enable"
echo 1 > "$TR/events/fastrpc/fastrpc_transport_response/enable"
echo 1 > "$TR/tracing_on"
echo "TRACE ON"
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64:/vendor/dsp/cdsp
export ADSP_LIBRARY_PATH=/vendor/dsp/adsp
export CDSP_LIBRARY_PATH=/vendor/dsp/cdsp
export GENIEX_LOG_LEVEL=off
export GENIEX_PLUGIN_PATH=/data/local/tmp/plug
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
TOK=$MODEL/tokenizer.json
cd /data/local/tmp
./geniex_client2 "$MODEL" "$TOK" 2>&1
echo "CLIENT_EXIT=$?"
echo 0 > "$TR/tracing_on"
cat "$TR/trace" > "$OUT"
echo "=== SAVED ==="
wc -l "$OUT"
echo "=== EVENTS ==="
grep -c "fastrpc_" "$OUT"
grep "fastrpc_" "$OUT" | tail -50
