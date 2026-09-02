#!/system/bin/sh
# run_mtp_readme.sh — Test MTP strictement selon runtime_apk/README_INTEGRATION_APK.md
# llama-server --spec-type draft-mtp -ngl 99 -t 8
# Usage: sh run_mtp_readme.sh [n_predict] [port]
NP=${1:-16}
PORT=${2:-8080}
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
SERVER=/data/local/tmp/npu/llama-server
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/run_mtp_readme.out
LOG=$LOG_SERVER
MON=/data/local/tmp/run_mtp_readme.monitor.csv
[ -z "$LOG_SERVER" ] && LOG=/data/local/tmp/run_mtp_readme_server.log
THREADS=8

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
export GGML_HEXAGON_MAX_MUL_MAT_ROWS=32768

: > "$OUT"
: > "$MON"
echo "START $(date +%s%3N)" >> "$MON"

# monitor toutes les ~1s
( while true; do
    T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -z "$T" ] && T=0
    HVX=""; for z in /sys/class/thermal/thermal_zone*; do
      case "$(cat $z/type 2>/dev/null)" in nsphvx-*) HVX="$HVX $(cat $z/temp 2>/dev/null)";; esac; done
    G=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null); [ -z "$G" ] && G=0
    echo "$(date +%s%3N),t0=$T,hvx=[$HVX],gpu=$G" >> "$MON"
    usleep 1000000 2>/dev/null || sleep 1
  done ) & MPID=$!

echo "=== MTP server start $(date +%s%3N) n_predict=$NP port=$PORT ===" >> "$OUT"
"$SERVER" -m "$M" -dev HTP0 -t "$THREADS" \
    --spec-type draft-mtp --ctx-size 4096 \
    --port "$PORT" --host 127.0.0.1 \
    -ngl 99 -c 4096 \
    > "$LOG" 2>&1 &
SPID=$!

i=0; READY=0
while [ $i -lt 240 ]; do
  sleep 1; i=$((i+1))
  if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q 200; then
    READY=1; break
  fi
  kill -0 $SPID 2>/dev/null || break
  # anticiper le SPIN hang : si "SPIN" dans le log depuis un moment, couper
done

if [ "$READY" = 1 ]; then
  echo "SERVER_READY after ${i}s" >> "$OUT"
  BODY=$(printf '{"prompt":"Why is the sky blue? Explain in three sentences.","n_predict":%s,"temperature":0,"stream":false}' "$NP")
  echo "SEND completion n_predict=$NP" >> "$OUT"
  curl -s -X POST "http://127.0.0.1:$PORT/completion" -H "Content-Type: application/json" -d "$BODY" > /data/local/tmp/run_mtp_readme_resp.json 2>> "$OUT"
  echo "CURL_RET=$?" >> "$OUT"
else
  echo "SERVER_FAILED (not ready in 240s or crashed) — last log:" >> "$OUT"
  tail -6 "$LOG" >> "$OUT"
fi

kill $SPID 2>/dev/null
kill -0 $MPID 2>/dev/null && kill $MPID 2>/dev/null
echo "DONE $(date +%s%3N)" >> "$MON"
echo "=== SUMMARY ===" >> "$OUT"
echo "server_ready=$READY spin_count=$(grep -c SPIN "$LOG" 2>/dev/null) err46=$(grep -c 'last_err=46' "$LOG" 2>/dev/null)" >> "$OUT"
grep -aE "acceptance|draft|mean n_draft|t/s|tokens_predicted" "$LOG" 2>/dev/null | tail -10 >> "$OUT"