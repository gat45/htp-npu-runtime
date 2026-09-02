#!/system/bin/sh
# =========================================================================
# RUN_GUARDED_BENCH — protocole benchmark GARDÉ (v2, protocole team 2026-09-02)
#
# Applique la séquence imposée par l'audit :
#   KILL ALL                    → pkill générique + attente de mort complète
#   VERIFY NO LLAMA             → boucle kill -0 jusqu'à 0 process
#   VERIFY PORT FREE            → curl health DOIT échouer avant start
#   START                       → nohup avec chemin ABSOLU (argv complet)
#   VERIFY PID + HEALTH         → kill -0 + health ok
#   WARMUP                      → 1 requête 4 tokens (optionnel via WARMUP=1)
#   BENCH                       → 1 requête n_predict donné
#   SAVE                        → log + resp + PID + temp + mem dans OUT/
#   KILL + VERIFY CLEAN         → pkill + boucle jusqu'à 0 process
#
# Usage (device) :
#   sh run_guarded_bench.sh <label> <port> <n_predict> <prompt> [spec_args...]
#   Ex : sh run_guarded_bench.sh ngramA 8541 64 "texte..." --spec-default
#   Env : RUNTIME (def /data/local/tmp/npu), MODEL, OUT (def /data/local/tmp/bench_out)
#   WARMUP=1 active le warmup 4 tokens (défaut: 0)
#   KEEP_ALIVE=0 tue le serveur après le run (défaut), 1 = laisse vivant
#
# Sortie : OUT/<label>/ avec server.log, resp.json, meta.txt
#          stdout : "RESULT <label> tps=... accept=... mean_len=... T_start=... T_end=..."
# =========================================================================
RUNTIME="${RUNTIME:-/data/local/tmp/npu}"
MODEL="${MODEL:-/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf}"
OUT="${OUT:-/data/local/tmp/bench_out}"
BIN="$RUNTIME/llama-server"

LABEL="$1"; PORT="$2"; N="$3"; PROMPT="$4"; shift 4 2>/dev/null
SPEC_ARGS="$@"

mkdir -p "$OUT/$LABEL"
LOG="$OUT/$LABEL/server.log"
RESP="$OUT/$LABEL/resp.json"
META="$OUT/$LABEL/meta.txt"

export LD_LIBRARY_PATH="$RUNTIME"
export ADSP_LIBRARY_PATH="$RUNTIME"
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
cd "$RUNTIME"

fail() { echo "FAIL[$LABEL]: $1"; echo "FAIL[$LABEL]: $1" >> "$META"; exit 1; }

# ---------- 1+2. KILL ALL + VERIFY NO LLAMA ----------
pkill -f llama-server 2>/dev/null
i=0
while true; do
    n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
    [ "$n" = "0" ] && break
    i=$((i+1)); [ $i -ge 20 ] && fail "llama-server encore vivant apres 60s (n=$n)"
    sleep 3
done
sleep 2

# ---------- 3. VERIFY PORT FREE ----------
if curl -s -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q ok; then
    fail "port $PORT occupe AVANT start"
fi

# ---------- 4. START SERVER (chemin absolu) ----------
T_START=$(cat /sys/class/thermal/thermal_zone21/temp 2>/dev/null || echo 0)
nohup "$BIN" -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
    $SPEC_ARGS --host 127.0.0.1 --port "$PORT" > "$LOG" 2>&1 &
SRV=$!

# ---------- 5. VERIFY PID + HEALTH ----------
i=0; READY=0
while [ $i -lt 90 ]; do
    if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
    if ! kill -0 $SRV 2>/dev/null; then tail -5 "$LOG"; fail "serveur mort au chargement"; fi
    i=$((i+1)); sleep 3
done
[ "$READY" = "1" ] || fail "timeout health (90x3s) — log: $(tail -3 "$LOG")"

# PID réel du serveur lié au port
SRV_PID=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | awk 'NR==1{print $2}')

# ---------- 6. WARMUP (optionnel) ----------
if [ "$WARMUP" = "1" ]; then
    curl -s -X POST "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' \
        -d "{\"prompt\":\"hello\",\"n_predict\":4,\"temperature\":0}" > /dev/null 2>&1
    sleep 2
fi

# ---------- 7. BENCH ----------
curl -s -X POST "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' \
    -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$N,\"temperature\":0}" > "$RESP" 2>/dev/null
sleep 1
T_END=$(cat /sys/class/thermal/thermal_zone21/temp 2>/dev/null || echo 0)

# ---------- 8. SAVE meta ----------
{
    echo "label=$LABEL"; echo "port=$PORT"; echo "n_predict=$N"
    echo "spec_args=$SPEC_ARGS"; echo "server_pid=$SRV_PID"
    echo "T_start_c=$((T_START/1000))"; echo "T_end_c=$((T_END/1000))"
    echo "runtime=$RUNTIME"; echo "model=$MODEL"
    grep -E "eval time|prompt eval time|total time|draft acceptance|graphs reused" "$LOG" | tail -4 >> "$META"
} >> "$META" 2>/dev/null

TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$RESP" 2>/dev/null | head -1 | cut -d: -f2)
ACCEPT=$(grep -o 'draft acceptance = [0-9.]*' "$LOG" 2>/dev/null | tail -1 | awk '{print $4}')
MEANLEN=$(grep -o 'mean len = [0-9.]*' "$LOG" 2>/dev/null | tail -1 | awk '{print $4}')
echo "RESULT $LABEL tps=$TPS accept=$ACCEPT mean_len=$MEANLEN T=$((T_START/1000))->$((T_END/1000))C pid=$SRV_PID"

# ---------- 9. KILL + VERIFY CLEAN ----------
if [ "$KEEP_ALIVE" != "1" ]; then
    kill $SRV 2>/dev/null
    pkill -f llama-server 2>/dev/null
    i=0
    while true; do
        n=$(ps -A 2>/dev/null | grep llama-server | grep -v grep | wc -l)
        [ "$n" = "0" ] && break
        i=$((i+1)); [ $i -ge 15 ] && { echo "WARN[$LABEL]: $n process restants"; break; }
        sleep 2
    done
fi
echo "DONE $LABEL"