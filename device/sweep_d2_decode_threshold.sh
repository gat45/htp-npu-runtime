#!/system/bin/sh
# sweep_d2_decode_threshold.sh — Test #2 : seuil de hang du decode batch-1 pur.
# sweep -ngl 60/64/70/80/90 avec p=1 n=16 (decode pur, pas de prefill massif)
# pour isoler le ngl où le decode Mamba batch-1 hang (op_pending).
# Usage: sh sweep_d2_decode_threshold.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/sweep_dec.log
MON=/data/local/tmp/sweep_dec.monitor.csv
TIMEOUT=120

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

run() {
  local ngl=$1
  echo "=== ngl=$ngl dec-pure $(date +%s%3N) ===" >> "$OUT"
  timeout "$TIMEOUT" "$BENCH" -m "$M" -dev HTP0 -ngl "$ngl" -t 6 -p 1 -n 16 -r 1 \
    2>&1 | grep -aE "tg16|pp1|error|Abort|SPIN" >> "$OUT"
  echo ">>> ngl=$ngl rc=$? timeout=$TIMEOUT end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
}

run 60
run 64
run 70
run 80
run 90

kill $MPID 2>/dev/null
echo "=== DECODE THRESHOLD RESULT ==="
grep -aE "=== |>>> |tg16|qwen" "$OUT"