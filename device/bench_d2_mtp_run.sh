#!/system/bin/sh
# bench_d2_mtp.sh — llama-server --spec-type draft-mtp sur Qwen3.5-9B-D2-A-MTP.
# Mesure decode effectif + acceptance MTP + thermal/freqs. Single-shot via
# /completion (pas de setup curl supplémentaire : on utilise curl -s).
# Usage: sh bench_d2_mtp.sh [ngen] [port]
NGEN=${1:-64}
PORT=${2:-8034}
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
SERVER=/data/local/tmp/npu/llama-server
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/bench_mtp.log
MON=/data/local/tmp/bench_mtp.monitor.csv
THREADS=6

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
    CPUS=""
    for c in 0 1 2 3 4 5 6 7; do
      f=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null); [ -z "$f" ] && f=0
      CPUS="${CPUS}$f,"
    done
    G=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null); [ -z "$G" ] && G=0
    echo "$(date +%s%3N),t0=$T,hvx=[$NSPH ],cpu=[${CPUS%,}],gpu=$G" >> "$MON"
  done ) & MPID=$!

echo "=== MTP server start $(date +%s%3N) ngen=$NGEN ===" >> "$OUT"
"$SERVER" -m "$M" -dev HTP0 -t "$THREADS" \
    --spec-type draft-mtp --ctx-size 4096 \
    --port "$PORT" --host 127.0.0.1 \
    --n-gpu-layers 99 -c 4096 \
    > /data/local/tmp/mtp_server.log 2>&1 &
SPID=$!

# attendre la disponibilité du serveur (max 180s)
i=0
READY=0
while [ $i -lt 180 ]; do
  sleep 1; i=$((i+1))
  if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q 200; then
    READY=1; break
  fi
  # crash precoce -> stop
  kill -0 $SPID 2>/dev/null || break
done

if [ "$READY" = 1 ]; then
  echo "SERVER_READY t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
  PROMPT='<|im_start|>user\nPourquoi le ciel est bleu ? Explique en trois phrases.\n<|im_end|>\n<|im_start|>assistant\n'
  BODY="{\"prompt\":\"$PROMPT\",\"n_predict\":$NGEN,\"temperature\":0,\"stream\":false}"
  echo "P=$(date +%s%3N) send completion ngen=$NGEN" >> "$OUT"
  curl -s -X POST "http://127.0.0.1:$PORT/completion" \
       -H "Content-Type: application/json" -d "$BODY" > /data/local/tmp/mtp_resp.json 2>> "$OUT"
  echo "C=$(date +%s%3N) curl_ret=$? t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
else
  echo "SERVER_FAILED (not ready or crashed) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$OUT"
fi

kill $SPID 2>/dev/null
kill $MPID 2>/dev/null
echo "DONE $(date +%s%3N) end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MON"
echo "=== MTP RESULT ==="
tail -6 /data/local/tmp/mtp_server.log 2>/dev/null
echo "--- timings (si dispo) ---"
grep -aoE '\{[^}]*model_duration_ms[^}]*\}' /data/local/tmp/mtp_resp.json 2>/dev/null | head -1
echo "--- resp keys ---"
head -c 400 /data/local/tmp/mtp_resp.json 2>/dev/null