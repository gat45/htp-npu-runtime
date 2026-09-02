#!/system/bin/sh
# sweep_d2_ngl.sh — sweep -ngl 48/64/80/99 sur D2-A-MTP (9B GGML HTP) en un seul
# process shell (session CDSP unique), pp128 / n32, monitoring thermal+freqs.
# Usage: sh sweep_d2_ngl.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/sweep_d2.log
MON=/data/local/tmp/sweep_d2.monitor.csv
TIMEOUT=${SWEEP_POINT_TIMEOUT:-300}   # secondes max / point (ngl99 est pathologique)

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400
export GGML_HEXAGON_USE_HMX=1

: > "$OUT"
echo "START $(date +%s%3N) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" > "$MON"

# Monitoring parallèle pendant tout le run
( while true; do
    T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z "$T" ] && T=0
    NSPH=""
    for z in /sys/class/thermal/thermal_zone*; do
      case "$(cat $z/type 2>/dev/null)" in nsphvx-*) NSPH="$NSPH $(cat $z/temp 2>/dev/null)";; esac
    done
    CPUS=""
    for c in 0 1 2 3 4 5 6 7; do
      f=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null); [ -z "$f" ] && f=0
      CPUS="${CPUS}$f,"
    done
    G=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null); [ -z "$G" ] && G=0
    echo "$(date +%s%3N),t0=$T,hvx=[$NSPH ],cpu=[${CPUS%,}],gpu=$G" >> "$MON"
  done ) & MPID=$!

run_point() {
  local ngl=$1
  echo "=== POINT ngl=$ngl $(date +%s%3N) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) ===" >> "$OUT"
  timeout "$TIMEOUT" "$BENCH" -m "$M" -ngl "$ngl" -dev HTP0 -t 6 -p 128 -n 32 -r 1 2>&1 | \
    grep -aE "ngl|pp128|tg32|error|Aborted|n_gpu|model size" >> "$OUT"
  local rc=$?
  echo ">>> ngl=$ngl rc=$rc end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
}

run_point 48
run_point 64
run_point 80
run_point 99

kill $MPID 2>/dev/null
echo "SWEEP_DONE $(date +%s%3N) end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MON"
echo "=== SWEEP RESULT ==="
grep -aE "=== POINT|>>> ngl=|qwen35" "$OUT"