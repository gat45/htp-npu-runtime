#!/system/bin/sh
# measure_cooldown.sh — mesurer la courbe de refroidissement NPU (inter-burst).
# 1) chauffe le NPU avec un run MTP long (n_predict=256)
# 2) echantillonne nsphvx toutes les 2s jusqu'a <=50C
# Sortie : /data/local/tmp/cooldown.csv  (epoch_ms, hvx_mC, delta_sec, temp_C)
# Usage: sh measure_cooldown.sh [port] [heat_tokens]
PORT=${1:-9100}; HEAT=${2:-256}
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
SERVER=/data/local/tmp/npu/llama-server
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/cooldown.csv
: > "$OUT"
export LD_LIBRARY_PATH=$LIB ADSP_LIBRARY_PATH=$LIB GGML_HEXAGON_NDEV=1 GGML_HEXAGON_ARCH=v81 GGML_HEXAGON_MAX_MUL_MAT_ROWS=32768

hvxt(){ best=0; for z in /sys/class/thermal/thermal_zone*; do ty=$(cat "$z/type" 2>/dev/null); tv=$(cat "$z/temp" 2>/dev/null); case "$ty" in nsphvx-*) [ "$tv" -gt "$best" ] 2>/dev/null && best=$tv;; esac; done; echo "$best"; }

# 1) HEAT: run MTP 256 tokens
"$SERVER" -m "$M" -dev HTP0 -t 8 --spec-type draft-mtp --ctx-size 4096 \
    --port "$PORT" --host 127.0.0.1 -ngl 99 -c 4096 > /data/local/tmp/heat_server.log 2>&1 &
SP=$!
rd=0; j=0
while [ $j -lt 240 ]; do sleep 1; j=$((j+1))
  curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q 200 && { rd=1; break; }
  kill -0 $SP 2>/dev/null || break; done
if [ "$rd" = 1 ]; then
  _b=$(printf '{"prompt":"Explain the nature of gravity in detail","n_predict":%s,"temperature":0,"stream":false}' "$HEAT")
  curl -s -X POST "http://127.0.0.1:$PORT/completion" -H "Content-Type: application/json" -d "$_b" > /dev/null 2>&1
fi
kill $SP 2>/dev/null
sleep 1
TMAX=$(hvxt)
echo "HEAT_DONE T_max=$(($TMAX/1000))C"

# 2) COOLDOWN sampling toutes les 2s jusqu'a <=48C
T0=$(date +%s%3N)
SAME=0
log(){ echo "$(date +%s%3N),$(hvxt),$1" >> "$OUT"; }
while :; do
  T=$(hvxt)
  log "$(($(date +%s%3N)-T0))"
  TC=$((T/1000))
  [ "$TC" -le 48 ] && { log "$(($(date +%s%3N)-T0))"; echo "COOLDOWN_DONE T=$TC C"; break; }
  sleep 2
done