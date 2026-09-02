#!/system/bin/sh
# sweep_8b_multihpt.sh — multi-HTP NDEV=3 vs mono, sur Qwen3-8B-Q4_K_M HTP.
# Répartit le modèle sur HTP0/HTP1/HTP2 via -dev HTP0,HTP1,HTP2 + split tensor/row.
# Usage: sh sweep_8b_multihpt.sh
M=/data/local/tmp/Qwen3-8B-Q4_K_M.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/sweep_mh.log
MON=/data/local/tmp/sweep_mh.monitor.csv
TIMEOUT=240

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
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

run() {  # $1=tag, reste=args bench
  local tag=$1; shift
  echo "=== $tag $(date +%s%3N) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) ===" >> "$OUT"
  timeout "$TIMEOUT" "$BENCH" "$@" 2>&1 | grep -aE "pp64|tg32|error|Aborted|HEXAGON_NDEV|HTP[0-2] " >> "$OUT"
  local rc=$?
  echo ">>> $tag rc=$rc end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
}

# 1) mono HTP0 (référence, NDEV=1)
GGML_HEXAGON_NDEV=1 \
  run "mono_HTP0_ngl80" -m "$M" -dev HTP0 -ngl 80 -t 6 -p 64 -n 32 -r 1

# 2) multi-HTP I: 3 sessions layer-split, toute le modèle offloadé
GGML_HEXAGON_NDEV=3 \
  run "multi3_HTP_ngl99_layer" -m "$M" -dev HTP0,HTP1,HTP2 -ngl 99 -t 6 -p 64 -n 32 -r 1

# 3) multi-HTP II: tensor-split 33/33/34 row-parallel
GGML_HEXAGON_NDEV=3 \
  run "multi3_HTP_tensor_ts" -m "$M" -dev HTP0,HTP1,HTP2 -sm tensor -ts 33/33/34 -ngl 99 -t 6 -p 64 -n 32 -r 1

# 4) multi-HTP III: row-split
GGML_HEXAGON_NDEV=3 \
  run "multi3_HTP_row" -m "$M" -dev HTP0,HTP1,HTP2 -sm row -ts 33/33/34 -ngl 99 -t 6 -p 64 -n 32 -r 1

kill $MPID 2>/dev/null
echo "SWEEP_DONE $(date +%s%3N) end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MON"
echo "=== SWEEP MULTI-HTP RESULT ==="
grep -aE "=== |>>> |qwen" "$OUT"