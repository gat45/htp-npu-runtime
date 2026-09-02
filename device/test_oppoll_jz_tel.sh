#!/system/bin/sh
# test_oppoll_jz_tel.sh — A/B OPPOLL sur runtime JZ + télémétrie temps réel
# Usage: sh test_oppoll_jz_tel.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
BIN=/data/local/tmp/npu/llama-bench
OUT=/data/local/tmp/oppoll_jz_tel.out
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

: > "$OUT"
echo "TEL_START $(cat /sys/class/thermal/thermal_zone4/temp 2>/dev/null) $(date +%s%3N)" >> "$OUT"

run_cfg() {
  NAME="$1"   # env vars optionnelles via ENV_$NAME
  eval "EXTRA=\$ENV_$NAME"
  TEL=/data/local/tmp/tel_$NAME.log
  sh /data/local/tmp/telemetry_sampler.sh "$TEL" 1 120 &
  TELPID=$!
  sleep 2
  T1=$(date +%s%3N)
  env $EXTRA timeout 200 "$BIN" -m "$M" -dev HTP0 -ngl 33 -p 16 -n 16 -r 2 -t 8 >> "$OUT" 2>&1
  RC=$?
  T2=$(date +%s%3N)
  kill $TELPID 2>/dev/null
  echo "=== RUN [$NAME] RC=$RC wall_ms=$((T2-T1)) ===" >> "$OUT"
  echo "--- telemetry $NAME ---" >> "$OUT"
  head -1 "$TEL" >> "$OUT"
  tail -2 "$TEL" >> "$OUT"
  sleep 15
}

ENV_base=""
ENV_oppoll="GGML_HEXAGON_OPPOLL=1 GGML_HEXAGON_OPPOLL_US=500"
run_cfg "base"
run_cfg "oppoll"

echo "TEL_END $(cat /sys/class/thermal/thermal_zone4/temp 2>/dev/null) $(date +%s%3N)" >> "$OUT"
echo "DONE" >> "$OUT"