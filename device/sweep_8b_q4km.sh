#!/system/bin/sh
# sweep_8b_q4km.sh — sweep -ngl 16/32/48/64/80 sur Qwen3-8B-Q4_K_M HTP0,
# calibration BW_eff (ms/token decode par volume offloadé).
# Usage: sh sweep_8b_q4km.sh
M=/data/local/tmp/Qwen3-8B-Q4_K_M.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/sweep_8b.log
MON=/data/local/tmp/sweep_8b.monitor.csv
TIMEOUT=${SWEEP_POINT_TIMEOUT:-240}

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400
export GGML_HEXAGON_USE_HMX=1

: > "$OUT"
echo "START $(date +%s%3N) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" > "$MON"

( while true; do
    T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z "$T" ] && T=0
    NSPH=""
    for z in /sys/class/thermal/thermal_zone*; do
      case "$(cat $z/type 2>/dev/null)" in nsphvx-*) NSPH="$NSPH $(cat $z/temp 2>/dev/null)";; esac
    done
    echo "$(date +%s%3N),t0=$T,hvx=[$NSPH ]" >> "$MON"
  done ) & MPID=$!

run_point() {
  local ngl=$1
  echo "=== POINT ngl=$ngl $(date +%s%3N) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) ===" >> "$OUT"
  timeout "$TIMEOUT" "$BENCH" -m "$M" -ngl "$ngl" -dev HTP0 -t 6 -p 64 -n 32 -r 1 2>&1 | \
    grep -aE "ngl|pp64|tg32|error|Aborted" >> "$OUT"
  local rc=$?
  echo ">>> ngl=$ngl rc=$rc end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
}

run_point 16
run_point 32
run_point 48
run_point 64
run_point 80

kill $MPID 2>/dev/null
echo "SWEEP_DONE $(date +%s%3N) end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MON"
echo "=== SWEEP 8B RESULT ==="
grep -aE "=== POINT|>>> ngl=|qwen" "$OUT"