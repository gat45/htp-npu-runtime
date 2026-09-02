#!/system/bin/sh
# bench_mtp_2x5.sh — Design factoriel 2×5 : TOKEN COUNT × THERMAL, température CONTROLLED.
# PHASE COLD : chaque taille de run part de <=40C (cooldown entre chaque point).
#   -> isole l'EFFET TOKEN COUNT à température maîtrisée.
# PHASE HOT  : taille de run croissante SANS cooldown (accumulation).
#   -> isole l'EFFET THERMIQUE à charge comparable (départ hot).
# Usage: sh bench_mtp_2x5.sh "[16 32 64 128 256]" [port]
SEQS=${1:-"16 32 64 128 256"}
BASE_PORT=${2:-9000}
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
SERVER=/data/local/tmp/npu/llama-server
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/mtp_2x5.out
: > "$OUT"

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
export GGML_HEXAGON_MAX_MUL_MAT_ROWS=32768

log(){ echo "$(date +%H:%M:%S) $*" | tee -a "$OUT"; }
hvxt(){
  best=0
  for z in /sys/class/thermal/thermal_zone*; do
    ty=$(cat "$z/type" 2>/dev/null); tv=$(cat "$z/temp" 2>/dev/null)
    case "$ty" in nsphvx-*) [ "$tv" -gt "$best" ] 2>/dev/null && best=$tv;; esac
  done
  echo "$best"
}
cooldown_to(){ TGT=$1
  while :; do T=$(hvxt); [ $((T/1000)) -le $TGT ] && { log "  cooldown ok T=$((T/1000))C"; break; }; sleep 8; done
}

run_one(){ TAG=$1; NP=$2; PORT=$3; NOCOOL=${4:-0}
  SRV=/data/local/tmp/mtp_2x5_${TAG}_${NP}.log
  RSP=/data/local/tmp/mtp_2x5_${TAG}_${NP}.json
  T0=$(hvxt)
  "$SERVER" -m "$M" -dev HTP0 -t 8 --spec-type draft-mtp --ctx-size 4096 \
      --port "$PORT" --host 127.0.0.1 -ngl 99 -c 4096 > "$SRV" 2>&1 &
  SP=$!
  rd=0; j=0
  while [ $j -lt 240 ]; do sleep 1; j=$((j+1))
    curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q 200 && { rd=1; break; }
    kill -0 $SP 2>/dev/null || break
  done
  if [ "$rd" != 1 ]; then log "  [$TAG $NP] SERVER_FAILED"; kill $SP 2>/dev/null; return; fi
  _b=$(printf '{"prompt":"Explain the nature of gravity in detail.","n_predict":%s,"temperature":0,"stream":false}' "$NP")
  curl -s -X POST "http://127.0.0.1:$PORT/completion" -H "Content-Type: application/json" -d "$_b" > "$RSP" 2>> "$OUT"
  E=$(grep -aoE "eval time *= *[0-9.]+ ms / *[0-9]+ tokens *\( *[0-9.]+ ms per token, *[0-9.]+ tokens per second\)" "$SRV" | tail -1)
  A=$(grep -aoE "draft acceptance = [^\" ]*" "$SRV" | tail -1)
  T1=$(hvxt)
  kill $SP 2>/dev/null
  log "  [$TAG np=$NP] T_start=$((T0/1000))C T_end=$((T1/1000))C $E"
  log "  [$TAG np=$NP] $A"
}

# PHASE COLD : cooldown controlle avant CHAQUE point
log "#### PHASE COLD (cooldown <=40C avant chaque point) ####"
i=0; for NP in $SEQS; do i=$((i+1)); cooldown_to 40; run_one cold $NP $((BASE_PORT+i)) 0; done
# PHASE HOT : sans cooldown, accumulation directe du run N-1
log "#### PHASE HOT (sans cooldown, accumulation) ####"
i=0; for NP in $SEQS; do i=$((i+1)); run_one hot $NP $((BASE_PORT+10+i)) 1; done
echo "DONE_2x5" >> "$OUT"