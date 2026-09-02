#!/system/bin/sh
# bench_4b_v81_sustained.sh — bench Qwen3-4B-Instruct-2507 (dsp_arch v81)
# But : mesurer max tokens / moins de chauffe sur le plus petit bundle Qualcomm natif v81.
# Pas d'option --config (inexistante dans geniex-bench) : la config est lue du bundle.
# Usage: sh bench_4b_v81_sustained.sh [n_tokens] [sample_sec]
BUNDLE=/data/local/tmp/models/Qwen3-4B-Instruct-2507
NGEN=${1:-512}
SAMP_SEC=${2:-70}
LOG=/data/local/tmp/bench4b_v81_sustained.log
SAMP=/data/local/tmp/bench4b_v81_sustained.thermal.txt
SW=/data/local/tmp/geniex-bench

export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/qairt:/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/qairt:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp

echo "START temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" > "$SAMP"
echo "# bundle=$BUNDLE ngen=$NGEN" > "$LOG"
$SW --plugin qairt --device npu \
    -m "$BUNDLE" -p 128 -n "$NGEN" -r 1 \
     >> "$LOG" 2>&1 &
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
  NSV=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | tr '\n' ';')
  echo "S t=${i}s t0=${TV} max_t0=${MAX}C cpu6=${C6} all=${NSV}" >> "$SAMP"
  i=$((i+2)); sleep 2
done
wait $BPID
echo "EXIT=$? end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$SAMP"
echo "END" >> "$SAMP"
echo "=== bench log ==="
grep -a -E "decode=|prefill=|tokens/s|ttft|EXIT=" "$LOG"