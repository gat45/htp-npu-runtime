#!/system/bin/sh
# =========================================================================
# CONFIRMATION A/B — Marco-Nano MoE : gpu_htp_8020 (GPU 80% premier) vs htp_only
# Resultat campagne suspect : GPU-premier 39,1 t/s vs HTP pur 30,6
# (l'inverse du Qwen dense ou HTP pur etait optimum)
# Protocole : A B A B, n_predict=200, cooldown <45C
# =========================================================================
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Marco-Nano-Instruct.Q4_0.gguf
OUT=/data/local/tmp/moe_ab
PORT=8595
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
        if [ "$T" -le 43000 ] 2>/dev/null; then return 0; fi
        sleep 10; i=$((i+1))
    done
    echo "WARN: temp >43C"
}

run_once() {
    LABEL=$1; DEV=$2; TS=$3
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
    echo "=== $LABEL dev=$DEV ts=$TS T_start=$((T_START/1000))C ==="
    if [ -n "$TS" ]; then
        nohup $BIN -m "$MODEL" -dev "$DEV" -ts "$TS" -ngl 99 -t 8 -c 2048 --fit off \
            --host 127.0.0.1 --port $PORT > "$D/server.log" 2>&1 &
    else
        nohup $BIN -m "$MODEL" -dev "$DEV" -ngl 99 -t 8 -c 2048 --fit off \
            --host 127.0.0.1 --port $PORT > "$D/server.log" 2>&1 &
    fi
    SRV=$!
    i=0; READY=0
    while [ $i -lt 90 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        if ! kill -0 $SRV 2>/dev/null; then echo "$LABEL SERVEUR MORT"; tail -4 "$D/server.log"; return 1; fi
        i=$((i+1)); sleep 3
    done
    [ "$READY" = "1" ] || { echo "$LABEL TIMEOUT"; return 1; }
    curl -s -X POST "http://127.0.0.1:$PORT/completion" \
        -H 'Content-Type: application/json' \
        -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$NPRED,\"temperature\":0}" \
        > "$D/resp.json" 2>/dev/null
    sleep 1
    T_END=$(get_temp)
    TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$D/resp.json" | head -1 | cut -d: -f2)
    PRED=$(grep -o '"tokens_predicted":[0-9]*' "$D/resp.json" | head -1 | cut -d: -f2)
    CNT=$(grep -o '"content":"[^"]*"' "$D/resp.json" | head -1 | cut -c1-60)
    echo "$LABEL dev=$DEV ts=${TS:-none} tps=$TPS predicted=$PRED T=$((T_START/1000))->$((T_END/1000))C" >> "$OUT/synthese.txt"
    echo "RESULT $LABEL : tps=$TPS T=$((T_START/1000))->$((T_END/1000))C"
    echo "  contenu: $CNT"
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
echo "CONFIG='Marco-Nano Q4_0 n_predict=$NPRED ordre A B A B'" > "$OUT/synthese.txt"
echo "A = htp_only (HTP0 pur) | B = gpu_htp_8020 (GPUOpenCL,HTP0 -ts 0.8,0.2)"
run_once moe_A1 "HTP0" ""
wait_cool
run_once moe_B1 "GPUOpenCL,HTP0" "0.8,0.2"
wait_cool
run_once moe_A2 "HTP0" ""
wait_cool
run_once moe_B2 "GPUOpenCL,HTP0" "0.8,0.2"
echo "=== DONE $(date) ==="
cat "$OUT/synthese.txt"
