#!/system/bin/sh
# npu_load_probe.sh — lance une inference QAIRT NPU et mesure l'activité réelle
# via fastrpc tracepoints (dspsignal + perf_counters) pendant l'exécution.
MODEL="/data/local/tmp/qwen3-8b-w4a16"
PY="/data/data/com.termux/files/usr/bin/python3.14"
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/gxlibs/qairt:/data/local/tmp/npu/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib/rfsa/adsp
export CDSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib/rfsa/adsp

# reset tracer
echo "0" > /sys/kernel/tracing/tracing_on 2>/dev/null || true
echo > /sys/kernel/tracing/trace 2>/dev/null || true
echo "fastrpc_dspsignal fastrpc_perf_counters fastrpc_transport_send" > /sys/kernel/tracing/set_event 2>/dev/null || true
echo "1" > /sys/kernel/tracing/tracing_on 2>/dev/null || true

# lance l'inference en arrière-plan
START=$(date +%s%N)
"$PY" /data/local/tmp/axe2_qairt_bench.py > /data/local/tmp/npu_probe_out.txt 2>&1 &
PID=$!
SLEEP_TOTAL=15
I=0
while [ $I -lt $SLEEP_TOTAL ] && kill -0 $PID 2>/dev/null; do
  sleep 1
  I=$((I+1))
done
END=$(date +%s%N)

# stop tracer
echo "0" > /sys/kernel/tracing/tracing_on 2>/dev/null || true
N_DS=$(grep -c 'fastrpc_dspsignal' /sys/kernel/tracing/trace 2>/dev/null || echo 0)
N_PERF=$(grep -c 'fastrpc_perf_counters' /sys/kernel/tracing/trace 2>/dev/null || echo 0)
N_TX=$(grep -c 'fastrpc_transport_send' /sys/kernel/tracing/trace 2>/dev/null || echo 0)

wait $PID 2>/dev/null || true
echo "=== RESULT ==="
echo "inference_wall_s=$(( (END-START)/1000000000 ))"
echo "fastrpc_dspsignal=$N_DS"
echo "fastrpc_perf_counters=$N_PERF"
echo "fastrpc_transport_send=$N_TX"
echo "rate_per_s=$(( (N_DS+N_PERF)/ (SLEEP_TOTAL>0?SLEEP_TOTAL:1) ))"
echo "=== bench output ==="
tail -5 /data/local/tmp/npu_probe_out.txt 2>/dev/null
echo "0" > /sys/kernel/tracing/set_event 2>/dev/null || true