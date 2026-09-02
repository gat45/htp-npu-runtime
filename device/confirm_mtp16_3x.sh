#!/system/bin/sh
# ===========================================================================
# CONFIRMATION 3x du run MTP 7,3 Go (8,80 t/s wall) — protocole PROTÉGÉ
#
# Règles (cf. RAPPORT_REBOOT_OOM_ET_PROTECTION) :
#   - départ froid < 45 C
#   - --fit off (HTP0 ne rapporte pas sa mémoire → sinon abort)
#   - kill IMMÉDIAT du serveur après la réponse (pas de process résiduel = OOM)
#   - seuil ZRAM : si /proc/swaps used > 5 Go → stop
#   - capture RAM (meminfo) pendant le run pour la preuve OOM
#
# Usage : sh confirm_mtp16_3x.sh
# Sortie : /data/local/tmp/confirm16/<run>.log + resp + mem
# ===========================================================================

RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
OUT=/data/local/tmp/confirm16
mkdir -p "$OUT"
PORT=8470

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

# --- seuil ZRAM : 0=OK 1=STOP ---
zram_over() {
    local used=$(awk '/zram/ {print $3}' /proc/swaps 2>/dev/null | head -1)
    [ -z "$used" ] && return 1
    [ "$used" -gt 5368709120 ] 2>/dev/null   # 5 Go en octets
}

# --- attendre départ froid < 45 C ---
i=0
while [ $i -lt 60 ]; do
    T=$(get_temp)
    if [ -n "$T" ] && [ "$T" -le 45000 ] 2>/dev/null; then break; fi
    echo "[WAIT] T=$((T/1000))C — attente <45C (${i}0s)..."
    sleep 10; i=$((i+1))
done
echo "TEMP_DEPART $(( $(get_temp) / 1000 ))C"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
cd $RUNTIME

R=1
while [ $R -le 3 ]; do
    pkill -f npu/llama-server 2>/dev/null; sleep 2

    echo "=== RUN $R/3 (départ $(( $(get_temp) / 1000 ))C) ==="
    nohup $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 8192 --fit off \
        --spec-type draft-mtp --host 127.0.0.1 --port $PORT \
        > "$OUT/run${R}.log" 2>&1 &
    SRV=$!

    # wait_ready (max 180 s — modèle 7,3 Go)
    i=0; READY=0
    while [ $i -lt 60 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        i=$((i+1)); sleep 3
    done

    if [ "$READY" = "1" ]; then
        # capture RAM pendant le run
        cat /proc/meminfo > "$OUT/run${R}_mem_before.txt"
        curl -s -X POST "http://127.0.0.1:$PORT/completion" \
            -H 'Content-Type: application/json' \
            -d '{"prompt":"The capital of France is","n_predict":16,"temperature":0}' \
            > "$OUT/run${R}_resp.json" 2>/dev/null
        cat /proc/meminfo > "$OUT/run${R}_mem_after.txt"
        awk '/zram/ {print "ZRAM_used=" $3/1073741824 " Go"}' /proc/swaps 2>/dev/null >> "$OUT/run${R}_mem_after.txt"
        TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/run${R}_resp.json" | head -1 | cut -d: -f2)
        echo "RUN $R : predicted_per_second=$TPS"
        grep -E "eval time|draft acceptance" "$OUT/run${R}.log" | tail -2
    else
        echo "RUN $R : ECHEC (serveur non prêt)"
        tail -3 "$OUT/run${R}.log"
    fi

    # === KILL IMMÉDIAT (protocole anti-OOM) ===
    kill $SRV 2>/dev/null
    sleep 1
    pkill -f npu/llama-server 2>/dev/null
    sleep 2
    echo "KILLED run $R — $(ps -A | grep llama | grep -v grep | wc -l) process restants"

    # seuil ZRAM
    if zram_over; then
        echo "ZRAM > 5 Go — STOP"
        exit 2
    fi
    R=$((R+1))
    sleep 15
done
echo "=== TERMINE ==="