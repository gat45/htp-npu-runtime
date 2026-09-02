#!/system/bin/sh
# =========================================================================
# BENCH A/B ALTERNE — ARGSORT sur HTP (A) vs CPU (B, via GGML_HEXAGON_OPFILTER)
# Modèle : Marco-Nano-Instruct.Q4_0 (MoE 8B/0,6B actifs, 256 experts top-8)
# n_predict=200 (assez long pour dépasser le bruit des runs 100 tokens)
# Ordre : A B A B — cooldown <45C entre runs
# Sortie : /data/local/tmp/argsort_ab/ + synthèse stdout
# =========================================================================
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf
OUT=/data/local/tmp/argsort_ab
PORT=8590
PROMPT="The capital of France is"
NPRED=200

mkdir -p "$OUT"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

get_temp() {
    for z in /sys/class/thermal/thermal_zone*; do
        t=$(cat "$z/type" 2>/dev/null)
        case "$t" in qmx-*)
            v=$(cat "$z/temp" 2>/dev/null)
            case "$v" in ''|*[!0-9]*) continue;; esac
            if [ "$v" -ge 30000 ] && [ "$v" -le 80000 ] 2>/dev/null; then echo "$v"; fi;;
        esac
    done | sort -n | tail -1
}

wait_cool() {
    i=0
    while [ $i -lt 60 ]; do
        T=$(get_temp)
        case "$T" in ''|*[!0-9]*) T=40000;; esac
        if [ "$T" -le 45000 ] 2>/dev/null; then return 0; fi
        sleep 10; i=$((i+1))
    done
    echo "WARN: temp >45C apres 10min"
}

run_once() {
    LABEL=$1; FILTER=$2
    D="$OUT/$LABEL"
    mkdir -p "$D"
    pkill -f llama-server 2>/dev/null
    i=0
    while [ $i -lt 20 ]; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); sleep 2
    done
    sleep 2
    T_START=$(get_temp)
    echo "=== $LABEL filter='$FILTER' T_start=$((T_START/1000))C ==="
    if [ -n "$FILTER" ]; then
        export GGML_HEXAGON_OPFILTER="$FILTER"
    else
        unset GGML_HEXAGON_OPFILTER
    fi
    nohup $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
        --host 127.0.0.1 --port $PORT > "$D/server.log" 2>&1 &
    SRV=$!
    i=0; READY=0
    while [ $i -lt 90 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        if ! kill -0 $SRV 2>/dev/null; then echo "$LABEL SERVEUR MORT"; tail -4 "$D/server.log"; return 1; fi
        i=$((i+1)); sleep 3
    done
    [ "$READY" = "1" ] || { echo "$LABEL TIMEOUT"; tail -4 "$D/server.log"; return 1; }

    curl -s -X POST "http://127.0.0.1:$PORT/completion" \
        -H 'Content-Type: application/json' \
        -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$NPRED,\"temperature\":0}" \
        > "$D/resp.json" 2>/dev/null
    sleep 1
    T_END=$(get_temp)
    TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$D/resp.json" | head -1 | cut -d: -f2)
    PRED=$(grep -o '"tokens_predicted":[0-9]*' "$D/resp.json" | head -1 | cut -d: -f2)
    echo "$LABEL filter=${FILTER:-none} tps=$TPS predicted=$PRED T=$((T_START/1000))->$((T_END/1000))C" >> "$OUT/synthese.txt"
    echo "RESULT $LABEL : tps=$TPS T=$((T_START/1000))->$((T_END/1000))C"
    kill $SRV 2>/dev/null
    pkill -f llama-server 2>/dev/null
    i=0
    while [ $i -lt 20 ]; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); sleep 2
    done
}

echo "START $(date)"
echo "CONFIG='Marco-Nano Q4_0 -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off n_predict=$NPRED'" > "$OUT/synthese.txt"
echo "HYPOTHESE: ARGSORT sur CPU (top-8 partiel) > ARGSORT HTP (tri 256 complet)"
run_once ab_A1 ""
wait_cool
run_once ab_B1 "ARGSORT"
wait_cool
run_once ab_A2 ""
wait_cool
run_once ab_B2 "ARGSORT"
echo "=== DONE $(date) ==="
cat "$OUT/synthese.txt"
