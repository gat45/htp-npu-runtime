#!/system/bin/sh
# ===========================================================================
# SWEEP SINGLES × VMEM 5/7/10 Go + MTP sur meilleure config
#
# Complète la matrice placement × VMEM : les singles (HTP0 seul, GPUOpenCL
# seul) n'avaient été testés qu'avec le VMEM par défaut (3,36 Go).
# On teste maintenant chaque single avec VMEM = 5/7/10 Go, puis MTP nmax1
# sur le meilleur couple (htp_only, champion mesuré 9,46 t/s).
#
# Protocole : 3 runs/config, thermique < 55 °C, kill par PID, JSON séparé.
# Usage : sh sweep_singles_vmem.sh [port_base]
# ===========================================================================

PORT_BASE=${1:-8260}
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/sweep_singles
mkdir -p "$OUT"

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

run_cfg() {
    LABEL=$1; DEVARG=$2; VMEM=$3; SPEC=$4
    PORT=$((PORT_BASE + ${5:-0}))
    echo "{" > "$OUT/$LABEL.json"
    echo "  \"config\": \"$LABEL\"," >> "$OUT/$LABEL.json"
    [ -n "$DEVARG" ] && echo "  \"dev\": \"$DEVARG\"," >> "$OUT/$LABEL.json" || echo "  \"dev\": \"CPU(pur)\"," >> "$OUT/$LABEL.json"
    [ -n "$VMEM" ] && echo "  \"vmem_mib\": $VMEM," >> "$OUT/$LABEL.json" || echo "  \"vmem_mib\": \"default\"," >> "$OUT/$LABEL.json"
    [ -n "$SPEC" ] && echo "  \"spec\": \"$SPEC\"," >> "$OUT/$LABEL.json"
    echo "  \"runs\": [" >> "$OUT/$LABEL.json"
    FIRST=1
    for R in 1 2 3; do
        LOG="$OUT/${LABEL}_r${R}.log"
        echo "[INFO] $LABEL run $R/3 (port $PORT) — démarrage serveur..."
        GGML_HEXAGON_VMEM=$VMEM $BIN -m "$MODEL" $DEVARG -ngl 99 -t 8 -c 2048 \
            --host 127.0.0.1 --port $PORT $SPEC > "$LOG" 2>&1 &
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
            ACC=$(grep -oE 'draft acceptance = [0-9.]+' "$LOG" | tail -1 | awk '{print $NF}')
            [ -z "$TPS" ] && TPS=0; [ -z "$PPT" ] && PPT=0
            [ -z "$ACC" ] && ACC=null
        else
            TPS=0; PPT=0; ACC=null
            echo "[ECHEC] $LABEL r$R : non prêt (log: $(tail -2 "$LOG" | tr '\n' ' '))"
        fi

        kill $SERVER_PID 2>/dev/null; sleep 2
        ps -A | grep llama | awk '{print $2}' | xargs -r kill -9 2>/dev/null
        sleep 2

        [ "$FIRST" = "1" ] || echo "," >> "$OUT/$LABEL.json"
        FIRST=0
        echo "    {\"run\":$R,\"tg_tps\":$TPS,\"pp_tps\":$PPT,\"acceptance\":$ACC}" >> "$OUT/$LABEL.json"
        echo "[$LABEL r$R] tg=$TPS pp=$PPT acc=$ACC"
        sleep 8
    done
    echo "  ]" >> "$OUT/$LABEL.json"
    echo "}" >> "$OUT/$LABEL.json"
}

# NOTE 2026-09-01 : forcer GGML_HEXAGON_VMEM au-delà de la limite mesurée
# (measure_max_vmem : allocations jusqu'à échec) provoque un spin RPC
# [dspcall] op_pending=1 last_err=46 = dépassement réel de la mémoire HTP.
# VMEM 5/7/10 Go occupent TOUTES les sessions HTP (3×3 runs = 9 échecs).
# → on teste MTP sur le champion avec le VMEM PAR DÉFAUT (la seule valeur qui
#   marche, mesurée = 9,46 t/s sur htp_only).

# MTP nmax1 sur le champion (HTP0 seul, VMEM défaut) — 3 runs
run_cfg "htp_mtp1" "-dev HTP0" "" "--spec-type draft-mtp --spec-draft-n-max 1" 6

echo "=== RESUME ==="
for C in htp_vmem5 htp_vmem7 htp_vmem10 gpu_vmem5 gpu_vmem7 gpu_vmem10 htp_mtp1; do
    awk -v c="$C" '
        /"tg_tps"/ { gsub(/[\",]/,"",$0); n=split($0,a,":"); s+=a[n]; cnt++ }
        /"acceptance"/ { gsub(/[\",]/,"",$0); n=split($0,a,":"); if (a[n]!="null") acc+=a[n]; acnt++ }
        END { if (cnt>0) printf "  %-11s tg=%.3f t/s (n=%d)", c, s/cnt, cnt;
              if (acnt>0) printf "  acc=%.3f", acc/acnt; print "" }
    ' "$OUT/$C.json"
done
echo "=== TERMINE ==="
