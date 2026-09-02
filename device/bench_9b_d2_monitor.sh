#!/system/bin/sh
# bench_9b_d2_monitor.sh — bench GGML 9B D2-A-MTP avec monitoring complet.
# Capture pendant le decode : temp t0/nsphvx/nsphmx + freq CPU0-7/GPU/NPU(clock vote).
# Usage: sh bench_9b_d2_monitor.sh [ngl] [p] [n] [mbuf]
NGL=${1:-60}
PP=${2:-64}
NGEN=${3:-32}
MBUF=${4:-3400}
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
LOG=/data/local/tmp/bench9b_d2.log
MON=/data/local/tmp/bench9b_d2.monitor.csv

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=$MBUF
export GGML_HEXAGON_USE_HMX=1

echo "START $(date +%s%3N) ngl=$NGL pp=$PP n=$NGEN mbuf=$MBUF" > "$MON"
$BENCH -m "$M" -ngl "$NGL" -p "$PP" -n "$NGEN" -r 1 -t 6 \
    -dev HTP0 > "$LOG" 2>&1 &
BPID=$!
i=0
MAXT=0
while [ $i -lt 90 ]; do
  kill -0 $BPID 2>/dev/null || break
  T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z "$T" ] && T=0
  [ $T -gt $MAXT ] && MAXT=$T
  NSPH=$(for z in /sys/class/thermal/thermal_zone*; do ty=$(cat $z/type 2>/dev/null);
         case $ty in nsphvx-*) echo -n "$(cat $z/temp 2>/dev/null) "; esac; done)
  CPUS=""
  for c in 0 1 2 3 4 5 6 7; do
    f=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null); [ -z "$f" ] && f=0
    CPUS="${CPUS}$f,"
  done
  G=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null); [ -z "$G" ] && G=0
  echo "$(date +%s%3N),t0=$T,max=$((MAXT/1000))C,cpu=[${CPUS%,}],gpu=$G,hvx=[${NSPH%,}]" >> "$MON"
  i=$((i+1)); sleep 1
done
wait $BPID
echo "EXIT=$? end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MON"
echo "=== bench log ==="
grep -aE "model size|model buffer|max mem|n_gpu|HTP|decode|pp50|tg50|load_time|sample_time|  pp|  tg|system_info" "$LOG" | head -40