#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu

FTRACE=/sys/kernel/tracing
RESULT=/data/local/tmp/bench_results
mkdir -p $RESULT

echo "=== CONFIGURE ftrace ==="
echo 0 > $FTRACE/tracing_on
echo 131072 > $FTRACE/buffer_size_kb 2>/dev/null
echo "" > $FTRACE/trace

echo 1 > $FTRACE/events/arm_smmu/map_pages/enable
echo 1 > $FTRACE/events/arm_smmu/unmap_pages/enable
echo 1 > $FTRACE/events/fastrpc/fastrpc_context_alloc/enable
echo 1 > $FTRACE/events/fastrpc/fastrpc_context_free/enable
echo 1 > $FTRACE/events/fastrpc/fastrpc_context_complete/enable
echo 1 > $FTRACE/events/fastrpc/fastrpc_dspsignal/enable
echo 1 > $FTRACE/events/fastrpc/fastrpc_transport_send/enable
echo 1 > $FTRACE/events/fastrpc/fastrpc_transport_response/enable

echo "ftrace enabled, launching bench..."
echo 1 > $FTRACE/tracing_on

# Run bench: 9B Q4_0, HTP0 only, 32 tokens, 2 reps
/data/local/tmp/npu/llama-bench \
  -m /data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf \
  -ngl 99 -t 8 -n 32 -r 2 \
  -dev HTP0 \
  2>&1 | tee $RESULT/decode_bench.txt

echo ""
echo "=== BENCH DONE, stopping ftrace ==="
echo 0 > $FTRACE/tracing_on

echo "=== SAVING ==="
cp $FTRACE/trace $RESULT/decode_ftrace_full.txt

echo "=== COUNTS ==="
grep -c "map_pages" $RESULT/decode_ftrace_full.txt > $RESULT/c_map.txt 2>/dev/null
grep -c "unmap_pages" $RESULT/decode_ftrace_full.txt > $RESULT/c_unmap.txt 2>/dev/null
grep -c "fastrpc_context_alloc" $RESULT/decode_ftrace_full.txt > $RESULT/c_alloc.txt 2>/dev/null
grep -c "fastrpc_context_free" $RESULT/decode_ftrace_full.txt > $RESULT/c_free.txt 2>/dev/null
grep -c "fastrpc_context_complete" $RESULT/decode_ftrace_full.txt > $RESULT/c_complete.txt 2>/dev/null
grep -c "fastrpc_transport_send" $RESULT/decode_ftrace_full.txt > $RESULT/c_send.txt 2>/dev/null
grep -c "fastrpc_transport_response" $RESULT/decode_ftrace_full.txt > $RESULT/c_resp.txt 2>/dev/null

echo "map_pages:          $(cat $RESULT/c_map.txt)"
echo "unmap_pages:        $(cat $RESULT/c_unmap.txt)"
echo "context_alloc:      $(cat $RESULT/c_alloc.txt)"
echo "context_free:       $(cat $RESULT/c_free.txt)"
echo "context_complete:   $(cat $RESULT/c_complete.txt)"
echo "transport_send:     $(cat $RESULT/c_send.txt)"
echo "transport_response: $(cat $RESULT/c_resp.txt)"

grep -E "map_pages|unmap_pages" $RESULT/decode_ftrace_full.txt > $RESULT/decode_map_only.txt 2>/dev/null
echo "map_only lines: $(wc -l < $RESULT/decode_map_only.txt)"

echo "=== DISABLE EVENTS ==="
echo 0 > $FTRACE/events/arm_smmu/map_pages/enable
echo 0 > $FTRACE/events/arm_smmu/unmap_pages/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_context_alloc/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_context_free/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_context_complete/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_dspsignal/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_transport_send/enable
echo 0 > $FTRACE/events/fastrpc/fastrpc_transport_response/enable

echo "=== DONE ==="
