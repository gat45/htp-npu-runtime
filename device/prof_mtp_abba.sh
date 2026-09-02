#!/system/bin/sh
# ABBA MTP — dissocie longueur vs thermique sur la chute 6.66 → 5.72
# Usage: sh prof_mtp_abba.sh <out_dir>
OUT="$1"; mkdir -p "$OUT"
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu
PORT=8098

read_gpu_temp() {
  local best=0
  for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      gpuss*) local v=$(cat "$z/temp" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$best" ] && best=$v ;;
    esac
  done
  echo $((best/1000))
}

wait_ready() {
  i=0
  while [ "$i" -lt 60 ]; do
    curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"' && return 0
    i=$((i+1)); sleep 2
  done
  return 1
}

run_one() {  # run_one <tag> <prompt> <n_predict> <pid_file>
  TAG="$1"; PROMPT="$2"; N="$3"
  pkill -f npu/llama-server 2>/dev/null; sleep 1
  T0=$(read_gpu_temp)
  nohup ./llama-server -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf \
      --spec-type draft-mtp -ngl 99 -t 8 -c 8192 \
      --port $PORT --host 127.0.0.1 > "$OUT/${TAG}_server.log" 2>&1 &
  SRV=$!
  wait_ready || { echo "FAIL $TAG server"; return 1; }
  # sonde en arrière-plan (durée max 240s)
  sh /data/local/tmp/qcmp/prof_telemetry.sh "$OUT/${TAG}_tele.csv" $SRV 240 > /dev/null 2>&1 &
  SONDE=$!
  echo "=== RUN $TAG temp_start=${T0}C n_predict=$N ==="
  # streaming + timestamps par token (date + contenu SSE)
  curl -sN -m 300 "http://127.0.0.1:$PORT/completion" \
    -H 'Content-Type: application/json' \
    -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$N,\"temperature\":0,\"stream\":true}" 2>/dev/null | \
    while IFS= read -r line; do
      echo "$(date +%s.%N) $line" >> "$OUT/${TAG}_stream.txt"
    done
  curl -s -m 30 "http://127.0.0.1:$PORT/completion" \
    -d "{\"prompt\":\"\",\"n_predict\":1,\"temperature\":0}" > /dev/null 2>&1
  kill $SONDE 2>/dev/null
  T1=$(read_gpu_temp)
  echo "=== DONE $TAG temp_end=${T1}C ==="
  grep -E 'draft acceptance' "$OUT/${TAG}_server.log" | tail -1
}

# ABBA : 16 froid → 64 chaud → [refroidir] → 64 froid → 16
run_one A_16t "The capital of France is" 16
run_one B_64t "Write a short paragraph about Paris" 64
echo "=== refroidissement 90s ==="
i=0; while [ "$i" -lt 90 ] && [ "$(read_gpu_temp)" -ge 50 ]; do sleep 5; i=$((i+5)); done
run_one C_64t_cold "Write a short paragraph about Paris" 64
run_one D_16t_cold "The capital of France is" 16
echo "=== ABBA complete ==="
