#!/system/bin/sh
# ===========================================================================
# CAMPAGNE FINALE — ABBA (16t/64t froid) + mémoire/thermique + 6 tests LLM
#
# Modèle cible : attnQ4 5,08 Go (sûr, zéro OOM) — runtime JZ npu/ (505354ed)
# Config : -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off
#          --spec-type draft-mtp --spec-draft-n-max 1
# Protocole : départ froid < 45 C, kill immédiat, mémoire+thermique par run
#
# Usage : sh repro16_final_abba.sh <out_dir>
# ===========================================================================

OUT="$1"; mkdir -p "$OUT"
RUNTIME=/data/local/tmp/npu
BIN=$RUNTIME/llama-server
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
PORT=8530
SPEC="--spec-type draft-mtp --spec-draft-n-max 1"

export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
cd $RUNTIME

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

# --- run: $1=label $2=n_predict $3=prompt $4=stream(0/1) ---
run_once() {
    LABEL=$1; N=$2; PROMPT=$3; STREAM=$4
    pkill -f npu/llama-server 2>/dev/null; sleep 2
    T_START=$(get_temp)
    nohup $BIN -m "$MODEL" -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off \
        $SPEC --host 127.0.0.1 --port $PORT > "$OUT/${LABEL}_server.log" 2>&1 &
    SRV=$!

    i=0; READY=0
    while [ $i -lt 60 ]; do
        if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then READY=1; break; fi
        if ! kill -0 $SRV 2>/dev/null; then break; fi
        i=$((i+1)); sleep 3
    done

    if [ "$READY" = "1" ]; then
        # mémoire avant
        grep -E "VmRSS|VmSize|RssAnon|RssFile|RssShmem|VmHWM|Threads" /proc/$SRV/status > "$OUT/${LABEL}_mem_before.txt" 2>/dev/null
        if [ "$STREAM" = "1" ]; then
            curl -sN -m 300 "http://127.0.0.1:$PORT/completion" \
                -H 'Content-Type: application/json' \
                -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$N,\"temperature\":0,\"stream\":true}" 2>/dev/null | \
                while IFS= read -r line; do echo "$(date +%s.%N) $line" >> "$OUT/${LABEL}_stream.txt"; done
        else
            curl -s -X POST "http://127.0.0.1:$PORT/completion" \
                -H 'Content-Type: application/json' \
                -d "{\"prompt\":\"$PROMPT\",\"n_predict\":$N,\"temperature\":0}" \
                > "$OUT/${LABEL}_resp.json" 2>/dev/null
        fi
        # mémoire après + thermique
        grep -E "VmRSS|VmSize|RssAnon|RssFile|RssShmem|VmHWM" /proc/$SRV/status > "$OUT/${LABEL}_mem_after.txt" 2>/dev/null
        T_END=$(get_temp)
        TPS=$(grep -o '"predicted_per_second":[0-9.]*' "$OUT/${LABEL}_resp.json" 2>/dev/null | head -1 | cut -d: -f2)
        echo "$LABEL: tps=$TPS T:$((T_START/1000))->$((T_END/1000))C"
        grep -E "eval time|draft acceptance|mean len|graphs reused" "$OUT/${LABEL}_server.log" | tail -3
    else
        echo "$LABEL: ECHEC"
        tail -3 "$OUT/${LABEL}_server.log"
    fi

    kill $SRV 2>/dev/null; sleep 1
    pkill -f npu/llama-server 2>/dev/null; sleep 2
    echo "$LABEL: KILLED ($(ps -A | grep llama | grep -v grep | wc -l) restants)"
    sleep 10
}

# --- ABBA : A_16t froid -> B_64t -> [refroidir] -> C_64t froid -> D_16t froid ---
run_once A_16t 16 "The capital of France is" 1
run_once B_64t 64 "Write a short paragraph about Paris" 1
echo "=== refroidissement 120s ==="
sleep 120
run_once C_64t_cold 64 "Write a short paragraph about Paris" 1
run_once D_16t_cold 16 "The capital of France is" 1

# --- 6 TESTS LLM FONCTIONNELS (déterministe, temperature=0) ---
echo "=== TESTS LLM ==="
run_once t1_knowledge 64 "Explain why the sky appears blue." 0
run_once t2_arith 64 "Calculate 17 * 23. Show the calculation." 0
run_once t3_logic 64 "If Alice is older than Bob and Bob is older than Carol, who is the youngest? Explain." 0
run_once t4_code 96 "Write a Python function that returns the Fibonacci sequence up to n." 0
run_once t5_long 192 "The history of artificial intelligence: from the Turing test to large language models." 0
run_once t6_repeat 64 "Write a haiku about autumn." 0

echo "=== TERMINE ==="