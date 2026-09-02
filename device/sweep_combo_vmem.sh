#!/system/bin/sh
# ===========================================================================
# SWEEP COMBINÉ CPU+HTP+GPU × VMEM HTP 5/7/10 Go
#
# But : tester les combinaisons de devices dans TOUS les ordres possibles,
#       avec 3 tailles de mémoire HTP (GGML_HEXAGON_VMEM = 5/7/10 Go).
#
# Contrainte fork JZ (prouvée) : `-dev` rejette "CPU" et ajoute le CPU
# (nullptr) automatiquement en FALLBACK DERNIÈRE POSITION. Donc :
#   - ordre NPU→GPU : -dev HTP0,GPUOpenCL   (CPU fallback après GPU)
#   - ordre GPU→NPU : -dev GPUOpenCL,HTP0   (CPU fallback après HTP)
#   - single NPU    : -dev HTP0
#   - single GPU    : -dev GPUOpenCL
#   - single CPU    : pas de -dev (défaut CPU pur)
#
# Protocole : 3 runs par config, thermique < 55 °C, kill par PID vérifié,
# JSON séparé par config, refroidissement 8 s entre runs.
#
# Usage : sh sweep_combo_vmem.sh [port_base]
# Sortie : /data/local/tmp/sweep_combo/<label>.json + logs
# ===========================================================================

PORT_BASE=${1:-8230}
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/sweep_combo
mkdir -p "$OUT"

# --- thermique -------------------------------------------------------------
TEMP=$(for z in /sys/class/thermal/thermal_zone*; do
          t=$(cat $z/type 2>/dev/null)
          case "$t" in *trip*|*lite*|*cpullc*) continue;; esac
          case "$t" in cpu*|soc*|npu*|ddr*|aoss*|qmx*) cat $z/temp 2>/dev/null;; esac
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

RESID=$(ps -A | grep llama | grep -v grep | wc -l)
if [ "$RESID" -gt 0 ]; then
    ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
    sleep 2
fi

# --- une config = 3 runs, JSON séparé --------------------------------------
# $1=label  $2=-dev args ("" = CPU pur)  $3=VMEM MiB ("" = défaut 3,36 Go)
run_cfg() {
    LABEL=$1; DEVARG=$2; VMEM=$3
    PORT=$((PORT_BASE + ${4:-0}))
    echo "{" > "$OUT/$LABEL.json"
    echo "  \"config\": \"$LABEL\"," >> "$OUT/$LABEL.json"
    [ -n "$DEVARG" ] && echo "  \"dev\": \"$DEVARG\"," >> "$OUT/$LABEL.json" || echo "  \"dev\": \"CPU(pur)\"," >> "$OUT/$LABEL.json"
    [ -n "$VMEM" ] && echo "  \"vmem_mib\": $VMEM," >> "$OUT/$LABEL.json" || echo "  \"vmem_mib\": \"default\"," >> "$OUT/$LABEL.json"
    echo "  \"runs\": [" >> "$OUT/$LABEL.json"
    FIRST=1
    for R in 1 2 3; do
        LOG="$OUT/${LABEL}_r${R}.log"
        echo "[INFO] $LABEL run $R/3 (port $PORT) — démarrage serveur..."
        if [ -n "$VMEM" ]; then
            GGML_HEXAGON_VMEM=$VMEM $BIN -m "$MODEL" $DEVARG -ngl 99 -t 8 -c 2048 \
                --host 127.0.0.1 --port $PORT > "$LOG" 2>&1 &
        else
            $BIN -m "$MODEL" $DEVARG -ngl 99 -t 8 -c 2048 \
                --host 127.0.0.1 --port $PORT > "$LOG" 2>&1 &
        fi
        SERVER_PID=$!

        READY=0; I=0
        while [ $I -lt 60 ]; do
            sleep 3
            if grep -qE "listening on http" "$LOG" 2>/dev/null; then READY=1; break; fi
            if grep -qE "error|failed|GGML_ASSERT|invalid device" "$LOG" 2>/dev/null && ! kill -0 $SERVER_PID 2>/dev/null; then break; fi
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

# --- singles (VMEM défaut — CPU n'utilise pas la mémoire HTP) --------------
run_cfg "cpu_only" "" "" 0
run_cfg "htp_only" "-dev HTP0" "" 1
run_cfg "gpu_only" "-dev GPUOpenCL" "" 2

# --- combos 2 devices × VMEM 5/7/10 Go -------------------------------------
run_cfg "htp_gpu_vmem5"  "-dev HTP0,GPUOpenCL" 5120  3
run_cfg "htp_gpu_vmem7"  "-dev HTP0,GPUOpenCL" 7168  4
run_cfg "htp_gpu_vmem10" "-dev HTP0,GPUOpenCL" 10240 5
run_cfg "gpu_htp_vmem5"  "-dev GPUOpenCL,HTP0" 5120  6
run_cfg "gpu_htp_vmem7"  "-dev GPUOpenCL,HTP0" 7168  7
run_cfg "gpu_htp_vmem10" "-dev GPUOpenCL,HTP0" 10240 8

echo "=== RESUME (moyennes) ==="
for C in cpu_only htp_only gpu_only htp_gpu_vmem5 htp_gpu_vmem7 htp_gpu_vmem10 gpu_htp_vmem5 gpu_htp_vmem7 gpu_htp_vmem10; do
    awk -v c="$C" '
        /"tg_tps"/ { gsub(/[\",]/,"",$0); n=split($0,a,":"); s+=a[n]; cnt++ }
        END { if (cnt>0) printf "  %-16s tg=%.3f t/s (n=%d)\n", c, s/cnt, cnt }
    ' "$OUT/$C.json"
done
echo "=== TERMINE ==="
