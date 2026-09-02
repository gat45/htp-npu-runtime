#!/system/bin/sh
# =========================================================================
# CAMPAIGN 3x300 — config gelée (attnQ4 + MTP n_max=1 + --fit off)
# 3 runs de n_predict=300, protocole gardé, cooldown entre runs
# Sortie : /data/local/tmp/camp_3x300/{r1,r2,r3}/ + synthese en stdout
# =========================================================================
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/camp_3x300
PORT=8520
PROMPT="The capital of France is"
COOLDOWN=25

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
    # attend T <= 45C (max 10 min)
    i=0
    while [ $i -lt 60 ]; do
        T=$(get_temp)
        case "$T" in ''|*[!0-9]*) T=40000;; esac
        if [ "$T" -le 45000 ] 2>/dev/null; then return 0; fi
        sleep 10; i=$((i+1))
    done
    echo "WARN: temp toujours >45C ($((T/1000))C) apres 10 min"
}

run_once() {
    LABEL=$1; N=$2
    D="$OUT/$LABEL"
    mkdir -p "$D"
    pkill -f llama-server 2>/dev/null
    i=0
    while [ $i -lt 15 ]; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); sleep 2
    done
    sleep 2
    T_START=$(get_temp)
    echo "=== $LABEL n_predict=$N T_start=$((T_START/1000))C ==="
    nohup $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
        --spec-type draft-mtp --spec-draft-n-max 1 \
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
        -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$N,\"temperature\":0}" \
        > "$D/resp.json" 2>/dev/null
    sleep 1
    T_END=$(get_temp)

    # parse
    TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$D/resp.json" | head -1 | cut -d: -f2)
    EVALT=$(grep -E "eval time" "$D/server.log" | tail -1 | grep -oE "[0-9]+\.[0-9]+ ms" | head -1)
    PRED=$(grep -o '"tokens_predicted":[0-9]*' "$D/resp.json" | head -1 | cut -d: -f2)
    ACC=$(grep -o 'draft acceptance = [0-9.]*' "$D/server.log" | tail -1 | awk '{print $4}')
    ML=$(grep -o 'mean len = [0-9.]*' "$D/server.log" | tail -1 | awk '{print $4}')
    echo "$LABEL tps=$TPS eval=$EVALT predicted=$PRED accept=$ACC mean_len=$ML T=$((T_START/1000))->$((T_END/1000))C" >> "$OUT/synthese.txt"
    echo "RESULT $LABEL : tps=$TPS accept=$ACC mean_len=$ML T=$((T_START/1000))->$((T_END/1000))C"

    kill $SRV 2>/dev/null
    pkill -f llama-server 2>/dev/null
    i=0
    while [ $i -lt 15 ]; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); sleep 2
    done
    echo "  process restants: $(ps -A | grep llama-server | grep -v grep | wc -l)"
}

echo "START $(date)"
echo "PROMPT='$PROMPT' CONFIG='-dev HTP0 -ngl 99 -t 8 -c 2048 --fit off --spec-type draft-mtp --spec-draft-n-max 1'" > "$OUT/synthese.txt"
run_once r1 300
wait_cool
run_once r2 300
wait_cool
run_once r3 300
echo "=== DONE $(date) ==="
echo "=== SYNTHESE (moyenne/ecart-type calcules cote hote) ==="
cat "$OUT/synthese.txt"
