#!/system/bin/sh
# =========================================================================
# TEST 16T/S SOUTENU — config gelée sur n_predict=100 puis 300
#
# Basé sur le pattern PROUVÉ de confirm_attnq4_mtp1_3x.sh (9,4-10,4 t/s x3):
#   - BIN full path (/data/local/tmp/npu/llama-server)
#   - pkill -f npu/llama-server (matche car argv complet)
#   - attendre <45C, --fit off, kill immédiat, seuil ZRAM 5 Go
#   - mesure VRAIE : eval time (wall) / tokens + predicted_per_second
#   - acceptance + mean_len (pour la formule effective historique)
#
# Usage : sh test_16tps_100_300.sh
# =========================================================================
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/test_16300
mkdir -p "$OUT"
PORT=8510
PROMPT="The capital of France is"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
cd $RUNTIME

get_temp() {
    for z in /sys/class/thermal/thermal_zone*; do
        t=$(cat $z/type 2>/dev/null)
        case "$t" in qmx-*|cpu-1*)
            v=$(cat $z/temp 2>/dev/null)
            case "$v" in ''|*[!0-9]*) continue;; esac
            if [ "$v" -ge 30000 ] && [ "$v" -le 80000 ] 2>/dev/null; then echo "$v"; fi;;
        esac
    done | sort -n | tail -1
}

phase() {
    LABEL=$1; N=$2
    pkill -f npu/llama-server 2>/dev/null; sleep 2
    T_START=$(get_temp)
    echo "=== $LABEL (n_predict=$N, T_depart=$((T_START/1000))C) ==="
    nohup $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
        --spec-type draft-mtp --spec-draft-n-max 1 \
        --host 127.0.0.1 --port $PORT > "$OUT/${LABEL}_server.log" 2>&1 &
    SRV=$!
    i=0; READY=0
    while [ $i -lt 90 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        if ! kill -0 $SRV 2>/dev/null; then echo "$LABEL SERVEUR MORT"; tail -4 "$OUT/${LABEL}_server.log"; return 1; fi
        i=$((i+1)); sleep 3
    done
    [ "$READY" = "1" ] || { echo "$LABEL TIMEOUT"; tail -4 "$OUT/${LABEL}_server.log"; return 1; }
    SRV_PID=$(ps -A | grep llama-server | grep -v grep | awk 'NR==1{print $2}')
    grep -E "VmRSS|VmHWM" /proc/$SRV_PID/status 2>/dev/null | sed 's/^/MEM /' >> "$OUT/${LABEL}_mem.txt"

    curl -s -X POST "http://127.0.0.1:$PORT/completion" \
        -H 'Content-Type: application/json' \
        -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$N,\"temperature\":0}" \
        > "$OUT/${LABEL}_resp.json" 2>/dev/null
    T_END=$(get_temp)
    TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/${LABEL}_resp.json" | head -1 | cut -d: -f2)
    EVAL=$(grep -E "eval time" "$OUT/${LABEL}_server.log" | tail -1)
    ACC=$(grep -o 'draft acceptance = [0-9.]*' "$OUT/${LABEL}_server.log" | tail -1)
    ML=$(grep -o 'mean len = [0-9.]*' "$OUT/${LABEL}_server.log" | tail -1)
    echo "RESULT $LABEL : predicted_per_second=$TPS"
    echo "  $EVAL"
    echo "  $ACC $ML"
    echo "  T=$((T_START/1000))C -> $((T_END/1000))C"
    kill $SRV 2>/dev/null; sleep 1
    pkill -f npu/llama-server 2>/dev/null; sleep 2
    echo "  process restants: $(ps -A | grep llama-server | grep -v grep | wc -l)"
    sleep 10
}

echo "START $(date)"
phase t100 100
phase t300 300   # enough cooldown + fresh server
echo "=== DONE ==="
echo; echo "=== SYNTHESE ==="
for L in t100 t300; do
    echo "--- $L ---"
    TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/${L}_resp.json" 2>/dev/null | head -1 | cut -d: -f2)
    EVAL=$(grep -E "eval time" "$OUT/${L}_server.log" 2>/dev/null | tail -1)
    ACC=$(grep -o 'draft acceptance = [0-9.]*' "$OUT/${L}_server.log" 2>/dev/null | tail -1 | awk '{print $4}')
    ML=$(grep -o 'mean len = [0-9.]*' "$OUT/${L}_server.log" 2>/dev/null | tail -1 | awk '{print $4}')
    echo "tps=$TPS accept=$ACC mean_len=$ML"
    echo "$EVAL"
done