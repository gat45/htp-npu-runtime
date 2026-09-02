#!/system/bin/sh
# ===========================================================================
# SWEEP RANDOMISÉ — protocole ABBA/blocs avec fenêtre thermique cible
#
# CORRECTION PROTOCOLE (2026-09-01) : l'ancienne campagne était en ordre
# BLOQUÉ (htp×3, gpu×3, ...) → le dernier groupe était pénalisé thermiquement.
# Ce script :
#   - ordre PSEUDO-ALÉATOIRE DIFFÉRENT pour chaque bloc (seed enregistré)
#   - 3 blocs × les 5 configs (CPU, HTP, GPU, HTP→GPU, GPU→HTP)
#   - attente entre runs jusqu'à revenir dans une FENÊTRE THERMIQUE CIBLE
#     (pas un délai fixe) : si T > cible, on attend et on relit
#   - T_start / T_end enregistrés pour CHAQUE run
#   - runtime, modèle, prompt, n_predict GELÉS (5,08 Go attnQ4 — NE PAS
#     mélanger avec la campagne 7,29 Go pour les gains)
#   - le baseline thermique + logiciel = htp_only 9,461 ± 0,323 t/s
#
# Usage : sh sweep_randomized.sh [port_base]
# Sortie : /data/local/tmp/sweep_rand/<bloc>.json + logs + seed
# ===========================================================================

PORT_BASE=${1:-8300}
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/sweep_rand
mkdir -p "$OUT"

# --- fenêtre thermique cible ----------------------------------------------
T_WINDOW_LO=43000   # 43 °C (cible de départ)
T_WINDOW_HI=50000   # 50 °C (rejet au-dessus)
T_BLOCK=55000       # blocage total au-dessus

# --- sonde thermique : zones CPU/NPU/DDR réelles UNIQUEMENT ----------------
# (les capteurs trip/lite/cpullc renvoient des valeurs parasites 95k ;
#  on filtre par nom ET on exclut le max aberrant > 85 C hors run)
get_temp() {
    # capteurs CPU/SoC réels uniquement ; plage 30-80 C (hors=parasite)
    for z in /sys/class/thermal/thermal_zone*; do
        t=$(cat $z/type 2>/dev/null)
        case "$t" in cpu-*|qmx-*|npu*)
            v=$(cat $z/temp 2>/dev/null)
            case "$v" in
                ''|*[!0-9]*) continue;;
            esac
            if [ "$v" -ge 30000 ] && [ "$v" -le 80000 ] 2>/dev/null; then
                echo "$v"
            fi ;;
        esac
    done | sort -n | tail -1
}

# attente de refroidissement : 60 s entre runs (chargement + mesure courts ~5 s)
# avec re-vérification : si toujours > 50 C après 60 s, on attend encore 30 s
COOLDOWN_S=60

echo "TEMP_INITIALE $(( $(get_temp) / 1000 ))C"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

# --- fenêtre thermique : attendre jusqu'à être dans la cible ---------------
wait_cool() {
    # attend le refroidissement (min COOLDOWN_S) puis vérifie la fenêtre
    sleep $COOLDOWN_S
    while :; do
        T=$(get_temp)
        if [ -z "$T" ]; then sleep 5; continue; fi
        if [ "$T" -gt $T_BLOCK ] 2>/dev/null; then
            echo "[WAIT] $1 T=$((T/1000))C > 55C blocage — attente 60s"
            sleep 60
        elif [ "$T" -gt $T_WINDOW_HI ] 2>/dev/null; then
            echo "[WAIT] $1 T=$((T/1000))C > 50C fenêtre — attente 30s"
            sleep 30
        else
            return 0
        fi
    done
}

RESID=$(ps -A | grep llama | grep -v grep | wc -l)
if [ "$RESID" -gt 0 ]; then
    ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
    sleep 2
fi

# --- configs (label ; devarg) — UNE LIGNE par config -----------------------
# Seules les combinaisons VALIDES sur ce fork (CPU = fallback implicite final)
## format : label;devarg  (devarg vide = CPU pur)
CONFIGS_LINES='cpu_only;
HTP_only;HTP0
GPU_only;GPUOpenCL
HTP_GPU;HTP0,GPUOpenCL
GPU_HTP;GPUOpenCL,HTP0'

# seed : horodatage (enregistré pour reproductibilité) — on le fixe
SEED=$(date +%s)
echo "SEED=$SEED" > "$OUT/seed.txt"
echo "{\"protocol\":\"randomized-blocks-thermal-window\",\"seed\":$SEED,\"model\":\"Qwen3.5-9B-D2-A-MTP-attnQ4 5.08GiB\",\"runtime\":\"npu/\"}" > "$OUT/meta.json"

get_cfg_name() { echo "$1" | cut -d';' -f1; }
get_cfg_dev()  { echo "$1" | cut -d';' -f2-; }

# --- 3 blocs : ordre pseudo-aléatoire différent par bloc --------------------
B=1
while [ $B -le 3 ]; do
    # génère l'ordre du bloc à partir du seed (déterministe, seed + bloc)
    # awk PRNG fait l'affaire (seed dérivé)
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
        if [ -z "$DEVNAME" ]; then
            DEVARG=""
        else
            DEVARG="-dev $DEVNAME"
        fi
        PORT=$((PORT_BASE + B * 10 + $(echo -n "$LABEL" | wc -c)))
        RUNDIR="$OUT/bloc${B}_${LABEL}"
        mkdir -p "$RUNDIR"

        wait_cool "$LABEL"
        T_START=$(get_temp)
        LOG="$RUNDIR/run.log"
        echo "[BLOC $B] $LABEL — démarrage (T=$((T_START/1000))C)..."
        $BIN -m "$MODEL" $DEVARG -ngl 99 -t 8 -c 2048 \
             --host 127.0.0.1 --port $PORT > "$LOG" 2>&1 &
        SERVER_PID=$!

        READY=0; I=0
        while [ $I -lt 60 ]; do
            sleep 3
            if grep -qE "listening on http" "$LOG" 2>/dev/null; then READY=1; break; fi
            # ne considérer que les ERREURS REELLES (les warnings "unused tensor"
            # ne sont pas fatals) ; si le serveur est mort = échec
            if grep -qE ": error|GGML_ASSERT|invalid device" "$LOG" 2>/dev/null && ! kill -0 $SERVER_PID 2>/dev/null; then break; fi
            I=$((I+1))
        done

        T0=$(date +%s)
        if [ "$READY" = "1" ]; then
            curl -s -X POST "http://127.0.0.1:$PORT/completion" \
                 -H 'Content-Type: application/json' \
                 -d '{"prompt":"The capital of France is","n_predict":32,"temperature":0}' \
                 > "$RUNDIR/resp.json" 2>/dev/null
            TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$RUNDIR/resp.json" | head -1 | cut -d: -f2)
            PPT=$(grep -o '"prompt_per_second":[0-9.]*' "$RUNDIR/resp.json" | head -1 | cut -d: -f2)
            ACC=$(grep -oE 'draft acceptance = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
            [ -z "$TPS" ] && TPS=0; [ -z "$PPT" ] && PPT=0
            [ -z "$ACC" ] && ACC=null
        else
            TPS=0; PPT=0; ACC=null
            echo "[ECHEC] $LABEL : non prêt (log: $(tail -2 "$LOG" | tr '\n' ' '))"
        fi
        T1=$(date +%s)
        DUREE=$((T1 - T0))
        T_END=$(get_temp)

        kill $SERVER_PID 2>/dev/null; sleep 2
        ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null

        [ "$FIRST" = "1" ] || echo "," >> "$OUT/bloc${B}.json"
        FIRST=0
        echo "    {\"config\":\"$LABEL\",\"tg_tps\":$TPS,\"pp_tps\":$PPT,\"acceptance\":$ACC,\"t_start_c\":$((T_START/1000)),\"t_end_c\":$((T_END/1000)),\"dur_s\":$DUREE}" >> "$OUT/bloc${B}.json"
        echo "[BLOC $B] $LABEL tg=$TPS pp=$PPT acc=$ACC T:$((T_START/1000))→$((T_END/1000))C (${DUREE}s)"
    done
    echo "  ]" >> "$OUT/bloc${B}.json"
    echo "}" >> "$OUT/bloc${B}.json"
    B=$((B+1))
done

echo "=== RESUME (3 blocs randomisés, seed $SEED) ==="
for C in cpu_only HTP_only GPU_only HTP_GPU GPU_HTP; do
    awk -v c="$C" '
        /"config"/ && index($0, "\"" c "\"") { gsub(/[\",]/,"",$0); n=split($0,a,":"); s+=a[n+2]; cnt++; ts+=substr($0,1) }
        END { if (cnt>0) printf "  %-9s (n=%d)\n", c, cnt }
    ' "$OUT"/bloc*.json 2>/dev/null
done
echo "=== voir bloc*.json pour le détail (tg par run) ==="
echo "=== TERMINE ==="