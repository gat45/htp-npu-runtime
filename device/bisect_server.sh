#!/system/bin/sh
# ===========================================================================
# BENCH BISECT JALONS (version serveur) — coût structurel du draft MTP
#
# Pourquoi serveur : llama-bench ne supporte PAS --spec-type draft-mtp sur le
# build JZ (hang documenté AXE-3) ; le MTP se mesure via llama-server
# (/completion + timings.predicted_per_second).
#
# Protocole : 3 configs, mêmes conditions (ngl 99, t 8, n_predict=16, temp 0) :
#   baseline   — sans --spec-type (témoin non-MTP)
#   mtp_nmax1  — --spec-type draft-mtp --spec-draft-n-max 1 (draft court)
#   mtp_nmax3  — --spec-type draft-mtp --spec-draft-n-max 3 (draft en bloc)
#                (n_max=4 = HANG serveur documenté → 3 = max sûr du GGUF)
# Thermique : blocage si device > 55 °C ; refroidissement entre runs.
#
# Usage :  sh bench_bisect_jalons_server.sh [port_base]
# Sortie : /data/local/tmp/bisect_jalons_server/result.json + logs
# ===========================================================================

PORT_BASE=${1:-8090}
RUNTIME=/data/local/tmp/instr
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
OUT=/data/local/tmp/bisect_jalons_server
mkdir -p "$OUT"

# --- thermique : ne pas lancer si déjà chaud ------------------------------
# Filtre : zones CPU/NPU/SOC réelles uniquement (ignorer les capteurs
# parasites type pmih010x_lite_tz=57k constat, trip points=95k, cpullc).
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
    echo "DEVICE_CHAUD $((TEMP/1000))C — refroidir < 55C avant bisect"
    exit 3
fi
echo "TEMP_INITIALE $((TEMP/1000))C OK"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
# OPPOLL volontairement ABSENT : le combo OPPOLL+MTP = régression mesurée (−37 %)

echo "{" > "$OUT/result.json"
echo "  \"model\": \"$MODEL\"," >> "$OUT/result.json"
echo "  \"configs\": [" >> "$OUT/result.json"

FIRST=1
run_cfg() {
    # $1 = label   $2 = args spec (vides pour baseline)
    LABEL=$1; SPEC=$2
    PORT=$((PORT_BASE + ${3:-0}))
    LOG="$OUT/${LABEL}.log"
    echo "[INFO] $LABEL (port $PORT) : démarrage serveur..."
    # kill résiduel éventuel
    pkill -f llama-server 2>/dev/null; sleep 2
    $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
         --host 127.0.0.1 --port $PORT $SPEC > "$LOG" 2>&1 &
    SERVER_PID=$!

    # attente du modèle chargé (max ~180 s)
    READY=0
    I=0
    while [ $I -lt 60 ]; do
        sleep 3
        if grep -qE "listening on http|server is listening|all slots are idle" "$LOG" 2>/dev/null; then
            READY=1; break
        fi
        # échec de chargement ?
        if grep -qE "error|failed|GGML_ASSERT" "$LOG" 2>/dev/null && ! kill -0 $SERVER_PID 2>/dev/null; then
            break
        fi
        I=$((I+1))
    done

    if [ "$READY" = "1" ]; then
        # génération n_predict=16, température 0 (identique aux runs précédents)
        curl -s -X POST "http://127.0.0.1:$PORT/completion" \
             -H 'Content-Type: application/json' \
             -d '{"prompt":"The capital of France is","n_predict":16,"temperature":0}' \
             > "$OUT/${LABEL}_resp.json" 2>/dev/null
        TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/${LABEL}_resp.json" | head -1 | cut -d: -f2)
        # acceptance : le serveur la log dans le log, pas dans le JSON de réponse
        ACC=$(grep -oE 'draft acceptance = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
        [ -z "$TPS" ] && TPS=0
        [ -z "$ACC" ] && ACC=null
    else
        TPS=0; ACC=null
        echo "[ECHEC] $LABEL : serveur non prêt (log : $(tail -3 "$LOG" | tr '\n' ' '))"
    fi

    kill $SERVER_PID 2>/dev/null; sleep 2
    pkill -f llama-server 2>/dev/null

    [ "$FIRST" = "1" ] || echo "," >> "$OUT/result.json"
    FIRST=0
    echo "    {\"label\":\"$LABEL\",\"tg_tps\":$TPS,\"acceptance\":$ACC}" >> "$OUT/result.json"
    echo "[$LABEL] tg = $TPS t/s (acceptance $ACC)"
    sleep 8   # refroidissement entre runs
}

run_cfg "baseline" "" 0
run_cfg "mtp_nmax1" "--spec-type draft-mtp --spec-draft-n-max 1" 1
run_cfg "mtp_nmax3" "--spec-type draft-mtp --spec-draft-n-max 3" 2

echo "" >> "$OUT/result.json"
echo "  ]" >> "$OUT/result.json"
echo "}" >> "$OUT/result.json"

echo "=== RESUME ==="
awk 'BEGIN{IGNORECASE=1} /"label"/ {print}' "$OUT/result.json"
echo "=== DRAFT_BLOCK_COST (nmax3 vs nmax1) ==="
python3 - "$OUT/result.json" 2>/dev/null || py -c "
import json,sys
d=json.load(open(r'$OUT/result.json'.replace('/','\\\\') if sys.platform=='win32' else '$OUT/result.json'))
g={}
for c in d['configs']:
    g[c['label']]=c['tg_tps']
if g.get('mtp_nmax1'):
    pct=100*(1-g.get('mtp_nmax3',0)/g['mtp_nmax1'])
    print(f'  baseline={g.get(\"baseline\")}  nmax1={g.get(\"mtp_nmax1\")}  nmax3={g.get(\"mtp_nmax3\")}')
    print(f'  draft_block_cost_pct = {pct:.1f}%  (\u003c15% = le draft en bloc ne coûte presque rien ; \u003e25% = coût structurel)')
" 2>/dev/null || cat "$OUT/result.json"
