#!/system/bin/sh
# =========================================================================
# CAMPAIGN RATIOS NPU x GPU — config 16 t/s gelée (attnQ4 + MTP n_max=1)
# Teste : HTP0 seul · GPUOpenCL seul · ordres HTP,GPU et GPU,HTP
#         × ratios -ts 80/20 · 50/50 · 20/80 — CPU en auto (fallback)
# Ordre randomisé seed 20260902, cooldown <45C entre runs, protocole gardé
# Sortie : /data/local/tmp/camp_ratios/{label}/ + synthese
# =========================================================================
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/camp_ratios
PORT=8550
PROMPT="The capital of France is"
NPRED=100
COOLDOWN_MAX=60   # 10 min max d'attente <45C

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
    while [ $i -lt $COOLDOWN_MAX ]; do
        T=$(get_temp)
        case "$T" in ''|*[!0-9]*) T=40000;; esac
        if [ "$T" -le 45000 ] 2>/dev/null; then return 0; fi
        sleep 10; i=$((i+1))
    done
    echo "WARN: temp >45C apres ${COOLDOWN_MAX}0s"
}

run_once() {
    LABEL=$1; DEV=$2; TS=$3
    D="$OUT/$LABEL"
    mkdir -p "$D"
    # kill propre
    pkill -f llama-server 2>/dev/null
    i=0
    while [ $i -lt 20 ]; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); sleep 2
    done
    sleep 2
    # port libre
    if curl -s -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q ok; then
        echo "FAIL[$LABEL]: port occupe"; return 1
    fi
    T_START=$(get_temp)
    echo "=== $LABEL dev=$DEV ts=$TS T_start=$((T_START/1000))C ==="
    # args speciaux : -ts seulement si fourni
    if [ -n "$TS" ]; then
        nohup $BIN -m "$MODEL" -dev "$DEV" -ts "$TS" -ngl 99 -t 8 -c 2048 --fit off \
            --spec-type draft-mtp --spec-draft-n-max 1 \
            --host 127.0.0.1 --port $PORT > "$D/server.log" 2>&1 &
    else
        nohup $BIN -m "$MODEL" -dev "$DEV" -ngl 99 -t 8 -c 2048 --fit off \
            --spec-type draft-mtp --spec-draft-n-max 1 \
            --host 127.0.0.1 --port $PORT > "$D/server.log" 2>&1 &
    fi
    SRV=$!
    i=0; READY=0
    while [ $i -lt 90 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        if ! kill -0 $SRV 2>/dev/null; then echo "$LABEL SERVEUR MORT"; tail -5 "$D/server.log"; return 1; fi
        i=$((i+1)); sleep 3
    done
    [ "$READY" = "1" ] || { echo "$LABEL TIMEOUT"; tail -5 "$D/server.log"; return 1; }

    curl -s -X POST "http://127.0.0.1:$PORT/completion" \
        -H 'Content-Type: application/json' \
        -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$NPRED,\"temperature\":0}" \
        > "$D/resp.json" 2>/dev/null
    sleep 1
    T_END=$(get_temp)

    TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$D/resp.json" | head -1 | cut -d: -f2)
    EVALT=$(grep -E "eval time" "$D/server.log" | tail -1 | grep -oE "[0-9]+\.[0-9]+ ms" | head -1)
    PRED=$(grep -o '"tokens_predicted":[0-9]*' "$D/resp.json" | head -1 | cut -d: -f2)
    ACC=$(grep -o 'draft acceptance = [0-9.]*' "$D/server.log" | tail -1 | awk '{print $4}')
    ML=$(grep -o 'mean len = [0-9.]*' "$D/server.log" | tail -1 | awk '{print $4}')
    # placement effectif : dernier split HTP0/GPU observe
    HTPLINE=$(grep -c "HTP0" "$D/server.log")
    GPULINE=$(grep -c "GPUOpenCL" "$D/server.log")
    echo "$LABEL dev=$DEV ts=$TS tps=$TPS eval=$EVALT predicted=$PRED accept=$ACC mean_len=$ML T=$((T_START/1000))->$((T_END/1000))C htp_lines=$HTPLINE gpu_lines=$GPULINE" >> "$OUT/synthese.txt"
    echo "RESULT $LABEL : tps=$TPS accept=$ACC mean_len=$ML T=$((T_START/1000))->$((T_END/1000))C"

    kill $SRV 2>/dev/null
    pkill -f llama-server 2>/dev/null
    i=0
    while [ $i -lt 20 ]; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); sleep 2
    done
    echo "  process restants: $(ps -A | grep llama-server | grep -v grep | wc -l)"
}

echo "START $(date)"
echo "CONFIG='attnQ4 + MTP n_max=1 + --fit off + -ngl 99 -t 8 -c 2048 n_predict=$NPRED CPU=auto'" > "$OUT/synthese.txt"

# Ordre randomisé (seed 20260902)
run_once gpu_only        "GPUOpenCL"         ""
wait_cool
run_once htp_gpu_5050    "HTP0,GPUOpenCL"    "0.5,0.5"
wait_cool
run_once gpu_htp_5050    "GPUOpenCL,HTP0"    "0.5,0.5"
wait_cool
run_once htp_only        "HTP0"              ""
wait_cool
run_once htp_gpu_8020    "HTP0,GPUOpenCL"    "0.8,0.2"
wait_cool
run_once gpu_htp_8020    "GPUOpenCL,HTP0"    "0.8,0.2"
wait_cool
run_once gpu_htp_2080    "GPUOpenCL,HTP0"    "0.2,0.8"
wait_cool
run_once htp_gpu_2080    "HTP0,GPUOpenCL"    "0.2,0.8"

echo "=== DONE $(date) ==="
cat "$OUT/synthese.txt"
