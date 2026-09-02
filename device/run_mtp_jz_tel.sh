#!/system/bin/sh
# run_mtp_jz_tel.sh — MTP sur runtime JZ (draft-mtp) ± OPPOLL + télémétrie temps réel
# Usage: sh run_mtp_jz_tel.sh <base|oppoll>
MODE="$1"; [ -z "$MODE" ] && MODE=base
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
DIR=/data/local/tmp/npu
BIN=$DIR/llama-server
OUT=/data/local/tmp/mtp_jz_${MODE}.out
TEL=/data/local/tmp/tel_mtp_${MODE}.log
PORT=8081
export LD_LIBRARY_PATH=$DIR
export ADSP_LIBRARY_PATH=$DIR
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
if [ "$MODE" = "oppoll" ]; then
  export GGML_HEXAGON_OPPOLL=1 GGML_HEXAGON_OPPOLL_US=500
fi

: > "$OUT"
echo "MTP_${MODE}_START temp=$(cat /sys/class/thermal/thermal_zone4/temp 2>/dev/null) $(date +%s%3N)" >> "$OUT"

# télémétrie
sh /data/local/tmp/telemetry_sampler.sh "$TEL" 1 300 &
TELPID=$!

# serveur
nohup $BIN -m "$M" --spec-type draft-mtp -ngl 33 -t 8 -c 2048 --port $PORT \
  --host 127.0.0.1 > /data/local/tmp/mtp_jz_srv_${MODE}.log 2>&1 &
SERVER_PID=$!
echo "SERVER_PID=$SERVER_PID" >> "$OUT"

# attendre health puis requête
READY=0
for i in $(seq 1 90); do
  sleep 3
  R=$(curl -s http://127.0.0.1:$PORT/health 2>/dev/null)
  case "$R" in *ok*|*ready*) READY=1; echo "SERVER_READY t+$((i*3))s temp=$(cat /sys/class/thermal/thermal_zone4/temp 2>/dev/null)" >> "$OUT"; break;; esac
done
if [ "$READY" = "1" ]; then
  T1=$(date +%s%3N)
  curl -s http://127.0.0.1:$PORT/completion \
    -d '{"prompt":"The capital of France is","n_predict":64,"temperature":0}' \
    > /data/local/tmp/mtp_jz_resp_${MODE}.json 2>&1
  T2=$(date +%s%3N)
  echo "COMPLETION wall_ms=$((T2-T1)) temp_end=$(cat /sys/class/thermal/thermal_zone4/temp 2>/dev/null)" >> "$OUT"
else
  echo "SERVER_NOT_READY" >> "$OUT"
fi
sleep 3
kill $SERVER_PID 2>/dev/null
sleep 2
kill $TELPID 2>/dev/null
echo "--- telemetry $MODE start/end ---" >> "$OUT"
head -1 "$TEL" >> "$OUT"
tail -1 "$TEL" >> "$OUT"
echo "MTP_${MODE}_END temp=$(cat /sys/class/thermal/thermal_zone4/temp 2>/dev/null) $(date +%s%3N)" >> "$OUT"
echo "DONE" >> "$OUT"