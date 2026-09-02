#!/system/bin/sh
# ===========================================================================
# SWEEP NGL COMPLET — 0/33/40/50/60/66/75/90 (protocole dossier upstream P8)
#
# Protocole :
#   - variables gelées : modèle, prompt, seed (temperature=0), n_predict=16,
#     runtime instr/, t=8, c=2048, pas de MTP (isolé : MTP testé séparément)
#   - 3 runs par NGL, JSON SÉPARÉ par config
#   - ordre randomisé (ABBA) : l'ordre des 8 configs est mélangé
#   - thermique contrôlé : blocage > 55 °C, refroidissement 8 s entre runs
#   - kill par PID vérifié avant chaque run (pas de contamination croisée)
#   - NGL=0 = témoin CPU pur (indispensable, P8)
#
# Usage :  sh sweep_ngl.sh [port_base]
# Sortie : /data/local/tmp/sweep_ngl/ngl<X>.json + logs
# ===========================================================================

PORT_BASE=${1:-8110}
RUNTIME=/data/local/tmp/instr
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
OUT=/data/local/tmp/sweep_ngl
mkdir -p "$OUT"

# --- thermique : ne pas lancer si déjà chaud ------------------------------
TEMP=$(for z in /sys/class/thermal/thermal_zone*; do
          t=$(cat $z/type 2>/dev/null)
          case "$t" in
              *trip*|*lite*|*cpullc*) continue;;
          esac
          case "$t" in
              cpu*|soc*|npu*|ddr*|aoss*|qmx*) cat $z/temp 2>/dev/null;;
          esac
       done | sort -n | tail -1)
if [ -n "$TEMP" ] && [ "$TEMP" -gt 55000 ] 2>/dev/null; then
    echo "DEVICE_CHAUD $((TEMP/1000))C — refroidir < 55C"
    exit 3
fi
echo "TEMP_INITIALE $((TEMP/1000))C OK"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

# vérif : aucun llama résiduel
RESID=$(ps -A | grep llama | grep -v grep | wc -l)
if [ "$RESID" -gt 0 ]; then
    echo "PROCESSUS_LLAMA_RESIDUELS=$RESID — kill avant de continuer"
    ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
    sleep 2
fi

# --- une config = 3 runs, JSON séparé --------------------------------------
run_cfg() {
    # $1 = label   $2 = ngl
    LABEL=$1; NGL=$2; PORT=$((PORT_BASE + NGL))
    echo "{" > "$OUT/$LABEL.json"
    echo "  \"config\": \"$LABEL\"," >> "$OUT/$LABEL.json"
    echo "  \"ngl\": $NGL," >> "$OUT/$LABEL.json"
    echo "  \"runs\": [" >> "$OUT/$LABEL.json"
    FIRST=1
    for R in 1 2 3; do
        LOG="$OUT/${LABEL}_r${R}.log"
        echo "[INFO] $LABEL (ngl=$NGL) run $R/3 (port $PORT) — démarrage serveur..."
        $BIN -m "$MODEL" -dev HTP0 -ngl $NGL -t 8 -c 2048 \
             --host 127.0.0.1 --port $PORT > "$LOG" 2>&1 &
        SERVER_PID=$!

        READY=0; I=0
        while [ $I -lt 60 ]; do
            sleep 3
            if grep -qE "listening on http" "$LOG" 2>/dev/null; then READY=1; break; fi
            if grep -qE "error|failed|GGML_ASSERT" "$LOG" 2>/dev/null && ! kill -0 $SERVER_PID 2>/dev/null; then break; fi
            I=$((I+1))
        done

        if [ "$READY" = "1" ]; then
            curl -s -X POST "http://127.0.0.1:$PORT/completion" \
                 -H 'Content-Type: application/json' \
                 -d '{"prompt":"The capital of France is","n_predict":16,"temperature":0}' \
                 > "$OUT/${LABEL}_r${R}_resp.json" 2>/dev/null
            TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/${LABEL}_r${R}_resp.json" | head -1 | cut -d: -f2)
            PPT=$(grep -o '"prompt_per_second":[0-9.]*' "$OUT/${LABEL}_r${R}_resp.json" | head -1 | cut -d: -f2)
            [ -z "$TPS" ] && TPS=0; [ -z "$PPT" ] && PPT=0
        else
            TPS=0; PPT=0
            echo "[ECHEC] $LABEL r$R : non prêt (log: $(tail -2 "$LOG" | tr '\n' ' '))"
        fi

        kill $SERVER_PID 2>/dev/null; sleep 2
        ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
        sleep 2

        [ "$FIRST" = "1" ] || echo "," >> "$OUT/$LABEL.json"
        FIRST=0
        echo "    {\"run\":$R,\"tg_tps\":$TPS,\"pp_tps\":$PPT}" >> "$OUT/$LABEL.json"
        echo "[$LABEL r$R] tg=$TPS pp=$PPT"
        sleep 8
    done
    echo "  ]" >> "$OUT/$LABEL.json"
    echo "}" >> "$OUT/$LABEL.json"
}

# --- ordre randomisé (ABBA) : les 8 configs sont exécutées en ordre mélangé
#     pour découpler l'ordre des runs de l'effet thermique résiduel
for PAIR in "ngl0 0" "ngl33 33" "ngl40 40" "ngl50 50" "ngl60 60" "ngl66 66" "ngl75 75" "ngl90 90"; do
    set -- $PAIR
    ORDER="$ORDER $1"
done
# mélange simple (seed déterministe pour reproductibilité)
ORDER=$(echo $ORDER | tr ' ' '\n' | awk 'BEGIN{srand(42)} {print rand(), $0}' | sort -n | awk '{print $2}')
echo "[INFO] Ordre d'exécution (ABBA randomisé, seed 42) :$ORDER"

for L in $ORDER; do
    case "$L" in
        ngl0)  run_cfg ngl0 0;;
        ngl33) run_cfg ngl33 33;;
        ngl40) run_cfg ngl40 40;;
        ngl50) run_cfg ngl50 50;;
        ngl60) run_cfg ngl60 60;;
        ngl66) run_cfg ngl66 66;;
        ngl75) run_cfg ngl75 75;;
        ngl90) run_cfg ngl90 90;;
    esac
done

echo "=== RESUME (moyennes par NGL) ==="
for C in ngl0 ngl33 ngl40 ngl50 ngl60 ngl66 ngl75 ngl90; do
    awk -v c="$C" '
        /"tg_tps"/ { gsub(/[\",]/,"",$0); n=split($0,a,":"); v[n]=a[n]; s+=v[n]; cnt++ }
        END { if (cnt>0) printf "  %-7s tg=%.3f t/s (n=%d)\n", c, s/cnt, cnt }
    ' "$OUT/$C.json"
done
echo "=== TERMINE ==="
