#!/system/bin/sh
# ===========================================================================
# MESURE RAM EXACTE : llama-server non-MTP vs MTP (surcoût des 2 contextes)
#
# Protocole :
#   - même modèle (attnQ4 5,08 Go — sûr, zéro crash), même ctx (c2048)
#   - non-MTP puis MTP (--spec-type draft-mtp --spec-draft-n-max 1)
#   - mesure via /proc/<pid>/status (VmRSS/RssAnon/RssFile/RssShmem/VmHWM)
#     + /proc/<pid>/smaps_rollup (Pss) au moment où le serveur est ready
#   - kill immédiat après mesure (protocole anti-OOM)
#
# Usage : sh measure_ram_mtp.sh
# Sortie : /data/local/tmp/ram_mtp/<mode>.txt (status + smaps)
# ===========================================================================

RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/ram_mtp
mkdir -p "$OUT"
PORT=8510

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
cd $RUNTIME

measure() {
    # $1 = label (nonmtp | mtp)   $2 = args spec ("" = non-MTP)
    LABEL=$1; SPEC=$2
    pkill -f npu/llama-server 2>/dev/null; sleep 2

    echo "=== $LABEL : démarrage serveur..."
    nohup $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
        $SPEC --host 127.0.0.1 --port $PORT > "$OUT/${LABEL}_server.log" 2>&1 &
    SRV=$!

    # wait_ready (le PID $! EST le processus llama-server sur Android)
    i=0; READY=0
    while [ $i -lt 60 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        # si le process est mort, on arrête d'attendre
        if ! kill -0 $SRV 2>/dev/null; then break; fi
        i=$((i+1)); sleep 3
    done

    if [ "$READY" = "1" ]; then
        PID=$SRV
        echo "=== $LABEL : PID=$PID (ready après ${i}x3s)"
        # status : VmPeak/VmSize/VmRSS/VmHWM/RssAnon/RssFile/RssShmem/Threads
        grep -E "VmPeak|VmSize|VmRSS|VmHWM|RssAnon|RssFile|RssShmem|Threads" /proc/$PID/status > "$OUT/${LABEL}_status.txt"
        # smaps_rollup : Rss/Pss/Shared_Clean/Shared_Dirty/Private_Clean/Private_Dirty
        cat /proc/$PID/smaps_rollup 2>/dev/null | grep -E "^Rss|^Pss|^Shared|^Private" > "$OUT/${LABEL}_smaps.txt"
        echo "--- status ---"
        cat "$OUT/${LABEL}_status.txt"
        echo "--- smaps_rollup ---"
        cat "$OUT/${LABEL}_smaps.txt"
    else
        echo "=== $LABEL : ECHEC (serveur non prêt, PID=$SRV vivant=$(kill -0 $SRV 2>/dev/null && echo oui || echo non))"
        tail -3 "$OUT/${LABEL}_server.log"
    fi

    # kill immédiat
    kill $SRV 2>/dev/null; sleep 1
    pkill -f npu/llama-server 2>/dev/null; sleep 2
    echo "=== $LABEL : KILLED ($(ps -A | grep llama | grep -v grep | wc -l) restants)"
    sleep 5
}

measure "nonmtp" ""
measure "mtp" "--spec-type draft-mtp --spec-draft-n-max 1"

echo "=== TERMINE ==="