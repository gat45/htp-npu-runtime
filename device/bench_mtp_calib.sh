#!/system/bin/sh
# bench_mtp_calib.sh — Calibration du chemin MTP 9B D2.
# Pour chaque n_predict dans la liste : serveur draft-mtp ngl99 t8, requete /completion,
# monitor thermique 500ms, decode tps + acceptance. Sequence froide->chaude.
# Usage: sh bench_mtp_calib.sh "[32 64 128 256]" [port]
SEQS=${1:-"32 64 128 256"}
BASE_PORT=${2:-8090}
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
SERVER=/data/local/tmp/npu/llama-server
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/mtp_calib.out
: > "$OUT"

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
export GGML_HEXAGON_MAX_MUL_MAT_ROWS=32768

log(){ echo "$(date +%H:%M:%S) $*" | tee -a "$OUT"; }

# monitor partage dans un tmp
MONLINE=/data/local/tmp/mtp_calib.mon
hvxt(){
  best=0
  for z in /sys/class/thermal/thermal_zone*; do
    ty=$(cat "$z/type" 2>/dev/null); tv=$(cat "$z/temp" 2>/dev/null)
    case "$ty" in nsphvx-*) [ "$tv" -gt "$best" ] 2>/dev/null && best=$tv;; esac
  done
  echo "$best"
}

i=0
for NP in $SEQS; do
  i=$((i+1)); PORT=$((BASE_PORT+i))
  SRVLOG=/data/local/tmp/mtp_calib_srv_$NP.log
  RESP=/data/local/tmp/mtp_calib_resp_$NP.json
  T0=$(hvxt)
  log "=== [$NP] start T_hvx=$((T0/1000))C port=$PORT ==="

  # monitor 500ms
  ( cur=$(hvxt); echo "$(date +%s%3N) $cur" > "$MONLINE";
    while true; do c=$(hvxt); echo "$(date +%s%3N) $c" >> "$MONLINE"; usleep 500000 2>/dev/null || sleep 1; done ) & MPID=$!

  "$SERVER" -m "$M" -dev HTP0 -t 8 --spec-type draft-mtp --ctx-size 4096 \
      --port "$PORT" --host 127.0.0.1 -ngl 99 -c 4096 > "$SRVLOG" 2>&1 &
  SPID=$!

  rd=0; j=0
  while [ $j -lt 240 ]; do sleep 1; j=$((j+1))
    curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q 200 && { rd=1; break; }
    kill -0 $SPID 2>/dev/null || break
  done
  if [ "$rd" != 1 ]; then log "  SERVER_FAILED [$NP]"; kill $SPID 2>/dev/null; kill $MPID 2>/dev/null; continue; fi

  _b=$(printf '{"prompt":"Explain the nature of gravity in detail.","n_predict":%s,"temperature":0,"stream":false}' "$NP")
  curl -s -X POST "http://127.0.0.1:$PORT/completion" -H "Content-Type: application/json" -d "$_b" > "$RESP" 2>> "$OUT"

  # decode tps + acceptance depuis le log serveur
  DTPS=$(grep -aoE "^0\.[0-9]+.*slot print_timing.*eval time[^)]*tokens per second\\)" "$SRVLOG" | tail -1)
  ACC=$(grep -aoE "draft acceptance = [^\"]*" "$SRVLOG" | tail -1)
  T1=$(hvxt)
  kill $SPID 2>/dev/null; kill -0 $MPID && kill $MPID 2>/dev/null
  log "  result[$NP]: $DTPS"
  log "  result[$NP]: $ACC  end_T_hvx=$((T1/1000))C"
done
kill -0 $MPID 2>/dev/null && kill $MPID 2>/dev/null
echo "DONE" >> "$OUT"