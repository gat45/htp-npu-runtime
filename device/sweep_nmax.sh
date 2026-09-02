#!/system/bin/sh
# ===========================================================================
# SWEEP N_MAX COMPLET — courbe baseline / nmax1 / nmax2 / nmax3
#
# Protocole propre (revue RED TEAM) :
#   - --fit off (ngl 99 explicite ; le fit auto avorte quand HTP0 ne
#     rapporte pas sa mémoire au 3e lancement consécutif)
#   - un seul process serveur à la fois (kill par PID vérifié avant chaque run)
#   - JSON SÉPARÉ par config (baseline.json / nmax1.json / ...)
#   - 3 runs par config (protocole : 3 minimum)
#   - thermique contrôlé (blocage > 55 °C, refroidissement 8 s entre runs)
#   - pas d'OPPOLL (combo OPPOLL+MTP = régression mesurée −37 %)
#
# Usage :  sh sweep_nmax.sh [port_base]
# Sortie : /data/local/tmp/sweep_nmax/<config>.json + logs
# ===========================================================================

PORT_BASE=${1:-8090}
RUNTIME=/data/local/tmp/instr
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
OUT=/data/local/tmp/sweep_nmax
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

# vérif : aucun llama résiduel (contamination croisée)
RESID=$(ps -A | grep llama | grep -v grep | wc -l)
if [ "$RESID" -gt 0 ]; then
    echo "PROCESSUS_LLAMA_RESIDUELS=$RESID — kill avant de continuer"
    ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
    sleep 2
fi

# --- une config = 3 runs, JSON séparé --------------------------------------
run_cfg() {
    # $1 = label   $2 = args spec (vides pour baseline)
    LABEL=$1; SPEC=$2
    PORT=$((PORT_BASE + ${3:-0}))
    echo "{" > "$OUT/$LABEL.json"
    echo "  \"config\": \"$LABEL\"," >> "$OUT/$LABEL.json"
    echo "  \"runs\": [" >> "$OUT/$LABEL.json"
    FIRST=1
    for R in 1 2 3; do
        LOG="$OUT/${LABEL}_r${R}.log"
        echo "[INFO] $LABEL run $R/3 (port $PORT) — démarrage serveur..."
        $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
             --host 127.0.0.1 --port $PORT $SPEC > "$LOG" 2>&1 &
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
            ACC=$(grep -oE 'draft acceptance = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
            MLEN=$(grep -oE 'mean len = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
            [ -z "$TPS" ] && TPS=0; [ -z "$PPT" ] && PPT=0
            [ -z "$ACC" ] && ACC=null; [ -z "$MLEN" ] && MLEN=null
        else
            TPS=0; PPT=0; ACC=null; MLEN=null
            echo "[ECHEC] $LABEL r$R : non prêt (log: $(tail -2 "$LOG" | tr '\n' ' '))"
        fi

        kill $SERVER_PID 2>/dev/null; sleep 2
        ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
        sleep 2

        [ "$FIRST" = "1" ] || echo "," >> "$OUT/$LABEL.json"
        FIRST=0
        echo "    {\"run\":$R,\"tg_tps\":$TPS,\"pp_tps\":$PPT,\"acceptance\":$ACC,\"mean_len\":$MLEN}" >> "$OUT/$LABEL.json"
        echo "[$LABEL r$R] tg=$TPS pp=$PPT acc=$ACC mean_len=$MLEN"
        sleep 8
    done
    echo "  ]" >> "$OUT/$LABEL.json"
    echo "}" >> "$OUT/$LABEL.json"
}

run_cfg "baseline" "" 0
run_cfg "nmax1" "--spec-type draft-mtp --spec-draft-n-max 1" 1
run_cfg "nmax2" "--spec-type draft-mtp --spec-draft-n-max 2" 2
run_cfg "nmax3" "--spec-type draft-mtp --spec-draft-n-max 3" 3

echo "=== RESUME (moyennes) ==="
for C in baseline nmax1 nmax2 nmax3; do
    awk -v c="$C" '
        /"tg_tps"/ { gsub(/[",]/,"",$0); n=split($0,a,":"); v[n]=a[n]; s+=v[n]; cnt++ }
        /"acceptance"/ { gsub(/[",]/,"",$0); n=split($0,a,":"); if (a[n]!="null") acc+=a[n]; acnt++ }
        END { if (cnt>0) printf "  %-9s tg=%.3f t/s (n=%d)", c, s/cnt, cnt;
              if (acnt>0) printf "  acc=%.3f (n=%d)", acc/acnt, acnt; print "" }
    ' "$OUT/$C.json"
done
echo "=== TERMINE ==="
