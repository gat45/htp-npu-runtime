#!/system/bin/sh
# bench_qairt_bundle.sh — bench QAIRT générique pour n'importe quel bundle.
# Usage: sh bench_qairt_bundle.sh <bundle> [n_tokens] [sample_sec]
BUNDLE="$1"
NGEN=${2:-512}
SAMP_SEC=${3:-70}
SW=/data/local/tmp/geniex-bench
LOGTAG=$(basename "$BUNDLE")
LOG=/data/local/tmp/benchq_${LOGTAG}.log
SAMP=/data/local/tmp/benchq_${LOGTAG}.thermal.txt

# IMPORTANT (fix E9) : /data/local/tmp/qairt en PRIORITÉ pour charger la bonne
# libgeniex_core.so (14/08), pas celle du 19/08 -> sinon segfault getQnnInterface.
export LD_LIBRARY_PATH=/data/local/tmp/qairt:/data/local/tmp/gxlibs:/data/local/tmp:/vendor/lib64:/system/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/qairt:/data/local/tmp/gxlibs:/data/local/tmp
export CDSP_LIBRARY_PATH=/data/local/tmp

echo "START temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" > "$SAMP"
echo "# bundle=$BUNDLE ngen=$NGEN" > "$LOG"
$SW --plugin qairt --device npu -m "$BUNDLE" -p 128 -n "$NGEN" -r 1 >> "$LOG" 2>&1 &
BPID=$!
i=0
MAX=0
while [ $i -lt $SAMP_SEC ]; do
  kill -0 $BPID 2>/dev/null || break
  TV=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  [ -z "$TV" ] && TV=0
  TOK=$((TV/1000))
  [ $TOK -gt $MAX ] && MAX=$TOK
  C6=$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq 2>/dev/null)
  echo "S t=${i}s t0=${TV} max_t0=${MAX}C cpu6=${C6}" >> "$SAMP"
  i=$((i+2)); sleep 2
done
wait $BPID
echo "EXIT=$? end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$SAMP"
echo "END" >> "$SAMP"
echo "=== bench log ==="
grep -a -E "decode=|prefill=|tokens/s|ttft|EXIT=" "$LOG"