#!/system/bin/sh
# ===========================================================================
# COMPLÉMENT SWEEP RANDOMISÉ — blocs 2-3 + config MTP16 (repro 16t/s)
#
# Objectif :
#   1. Compléter la matrice randomisée interrompue (blocs 2 et 3, 5 configs,
#      ordres différents seedés, fenêtre thermique, T_start/T_end par run)
#   2. Ajouter la config "mtp16" : modèle 7,30 Go + --spec-type draft-mtp
#      + n_predict=16 (exactement le run historique du 16,6 t/s effectifs)
#      dans le MÊME protocole randomisé → vérifier le 16t/s sous conditions
#      contrôlées (thermique 43-50 C, pas de dérive de fin de bloc).
#
# Usage : sh sweep_rand_mtp16.sh [port_base]
# Sortie : /data/local/tmp/sweep_rand2/<bloc>.json + logs
# ===========================================================================

PORT_BASE=${1:-8400}
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
OUT=/data/local/tmp/sweep_rand2
mkdir -p "$OUT"

# modèle par config : attnQ4 (5,08 Go) pour les 5 configs placement ;
# modèle complet 7,30 Go pour mtp16 (repro 16t/s)
MODEL_Q4=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
MODEL_FULL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf

# --- sonde thermique (CPU/SoC réels, plage 30-80 C) ---
get_temp() {
    for z in /sys/class/thermal/thermal_zone*; do
        t=$(cat $z/type 2>/dev/null)
        case "$t" in cpu-*|qmx-*|npu*)
            v=$(cat $z/temp 2>/dev/null)
            case "$v" in ''|*[!0-9]*) continue;; esac
            if [ "$v" -ge 30000 ] && [ "$v" -le 80000 ] 2>/dev/null; then echo "$v"; fi;;
        esac
    done | sort -n | tail -1
}

T_WINDOW_HI=50000
T_BLOCK=55000
COOLDOWN_S=60

wait_cool() {
    sleep $COOLDOWN_S
    while :; do
        T=$(get_temp)
        if [ -z "$T" ]; then sleep 5; continue; fi
        if [ "$T" -gt $T_BLOCK ] 2>/dev/null; then
            echo "[WAIT] $1 T=$((T/1000))C > 55C — attente 60s"; sleep 60
        elif [ "$T" -gt $T_WINDOW_HI ] 2>/dev/null; then
            echo "[WAIT] $1 T=$((T/1000))C > 50C — attente 30s"; sleep 30
        else
            return 0
        fi
    done
}

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

RESID=$(ps -A | grep llama | grep -v grep | wc -l)
if [ "$RESID" -gt 0 ]; then
    ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null; sleep 2
fi

SEED=$(date +%s)
echo "SEED=$SEED" > "$OUT/seed.txt"

# --- configs (label;devarg;model) ---
CONFIGS_LINES='cpu_only;;q4
HTP_only;HTP0;q4
GPU_only;GPUOpenCL;q4
HTP_GPU;HTP0,GPUOpenCL;q4
GPU_HTP;GPUOpenCL,HTP0;q4
mtp16;HTP0;full'

get_cfg_name() { echo "$1" | cut -d';' -f1; }
get_cfg_dev()  { echo "$1" | cut -d';' -f2; }
get_cfg_mod()  { echo "$1" | cut -d';' -f3; }

# --- 2 blocs restants (2 et 3) — ordre aléatoire seedé différent ---
B=2
while [ $B -le 3 ]; do
    ORDER=$(echo "$CONFIGS_LINES" | grep -v '^$' | awk -v s="$((SEED + B * 7919))" 'BEGIN{srand(s)} {print rand(), $0}' | sort -n | awk '{sub(/^[^ ]+ /, ""); print}')
    echo "[BLOC $B] ordre : $(echo $ORDER | tr '\n' ' ')"
    {
        echo "{"
        echo "  \"bloc\": $B,"
        echo "  \"runs\": ["
    } > "$OUT/bloc${B}.json"
    FIRST=1
    for CFG in $ORDER; do
        LABEL=$(get_cfg_name "$CFG")
        DEVNAME=$(get_cfg_dev "$CFG")
        MODKIND=$(get_cfg_mod "$CFG")
        [ "$MODKIND" = "full" ] && MODEL=$MODEL_FULL || MODEL=$MODEL_Q4
        if [ -z "$DEVNAME" ]; then DEVARG=""; else DEVARG="-dev $DEVNAME"; fi
        PORT=$((PORT_BASE + B * 10 + $(echo -n "$LABEL" | wc -c)))

        wait_cool "$LABEL"
        T_START=$(get_temp)
        LOG="$OUT/${B}_${LABEL}.log"
        echo "[BLOC $B] $LABEL ($MODKIND) — démarrage (T=$((T_START/1000))C)..."
        if [ "$LABEL" = "mtp16" ]; then
            $BIN -m "$MODEL" $DEVARG -ngl 99 -t 8 -c 8192 \
                --spec-type draft-mtp --host 127.0.0.1 --port $PORT > "$LOG" 2>&1 &
        else
            $BIN -m "$MODEL" $DEVARG -ngl 99 -t 8 -c 2048 \
                --host 127.0.0.1 --port $PORT > "$LOG" 2>&1 &
        fi
        SERVER_PID=$!

        READY=0; I=0
        while [ $I -lt 90 ]; do
            sleep 3
            if grep -qE "listening on http" "$LOG" 2>/dev/null; then READY=1; break; fi
            if grep -qE ": error|GGML_ASSERT|invalid device" "$LOG" 2>/dev/null && ! kill -0 $SERVER_PID 2>/dev/null; then break; fi
            I=$((I+1))
        done

        T0=$(date +%s)
        if [ "$READY" = "1" ]; then
            if [ "$LABEL" = "mtp16" ]; then
                N=16
            else
                N=32
            fi
            curl -s -X POST "http://127.0.0.1:$PORT/completion" \
                 -H 'Content-Type: application/json' \
                 -d "{\"prompt\":\"The capital of France is\",\"n_predict\":$N,\"temperature\":0}" \
                 > "$OUT/${B}_${LABEL}_resp.json" 2>/dev/null
            TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/${B}_${LABEL}_resp.json" | head -1 | cut -d: -f2)
            PPT=$(grep -o '"prompt_per_second":[0-9.]*' "$OUT/${B}_${LABEL}_resp.json" | head -1 | cut -d: -f2)
            ACC=$(grep -oE 'draft acceptance = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
            MLEN=$(grep -oE 'mean len = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
            [ -z "$TPS" ] && TPS=0; [ -z "$PPT" ] && PPT=0
            [ -z "$ACC" ] && ACC=null; [ -z "$MLEN" ] && MLEN=null
        else
            TPS=0; PPT=0; ACC=null; MLEN=null
            echo "[ECHEC] $LABEL : non prêt (log: $(tail -2 "$LOG" | tr '\n' ' '))"
        fi
        T1=$(date +%s)
        T_END=$(get_temp)

        kill $SERVER_PID 2>/dev/null; sleep 2
        ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null

        [ "$FIRST" = "1" ] || echo "," >> "$OUT/bloc${B}.json"
        FIRST=0
        echo "    {\"config\":\"$LABEL\",\"tg_tps\":$TPS,\"pp_tps\":$PPT,\"acceptance\":$ACC,\"mean_len\":$MLEN,\"t_start_c\":$((T_START/1000)),\"t_end_c\":$((T_END/1000)),\"dur_s\":$((T1-T0))}" >> "$OUT/bloc${B}.json"
        echo "[BLOC $B] $LABEL tg=$TPS acc=$ACC mean_len=$MLEN T:$((T_START/1000))->$((T_END/1000))C"
    done
    echo "  ]" >> "$OUT/bloc${B}.json"
    echo "}" >> "$OUT/bloc${B}.json"
    B=$((B+1))
done

echo "=== TERMINE (seed $SEED) ==="
