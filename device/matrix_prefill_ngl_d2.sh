#!/system/bin/sh
# matrix_prefill_ngl_d2.sh — MATRICE prefill × ngl (protocole red-team).
# 60/70/80/90/99 × p=1/32/128/512, decode n=16.
# MESURES correctes : rc RÉEL (exit de timeout), SPIN count, SPIN err46 count par point.
# Usage: sh matrix_prefill_ngl_d2.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/matrix_d2.log
TIMEOUT=90   # temps max PAR point (petit => balayage exhaustif)

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400
export GGML_HEXAGON_USE_HMX=1

: > "$OUT"

run() {  # $1=ngl $2=p
  local ngl=$1 p=$2 tag
  tag="${p}p_ngl${ngl}"
  local tmp=/data/local/tmp/$tag.brut
  echo "START $tag $(date +%s%3N) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
  timeout "$TIMEOUT" "$BENCH" -m "$M" -dev HTP0 -ngl "$ngl" -t 6 -p "$p" -n 16 -r 1 > "$tmp" 2>&1
  local rc=$?   # rc RÉEL du process llama-bench (0=terminé proprement, 124=timeout)
  local spin=$(grep -acE "SPIN waiting" "$tmp")
  local err46=$(grep -acE "op_pending=[0-9]+ last_err=46" "$tmp")
  # ligne brute des tps (la ligne qwen35 contenant pp/tg), sans les longs logs de split
  local tps=$(grep -aE "qwen35" "$tmp" | grep -avE "GET_ROWS|RESHAPE|VIEW" | tr '\n' '|')
  echo "RESULT $tag rc=$rc spin=$spin err46=$err46 tps=[$tps] end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
  rm -f "$tmp"
}

# Matrice : ngl lignes élevé, prefill colonnes
for ngl in 60 70 80 90 99; do
  for p in 1 32 128 512; do
    run "$ngl" "$p"
  done
done

echo "=== MATRIX RESULT (rc RÉEL, spin, err46) ==="
grep -aE "RESULT" "$OUT"