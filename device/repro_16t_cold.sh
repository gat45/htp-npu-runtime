#!/system/bin/sh
# REPRO 16t FROID — conditions historiques RAPPORT_MTP_ABBA_THERMIQUE (§ A_16t)
# Objectif : wall-clock du run 16 tokens à partir d'un départ froid (< 45 C),
# avec télémétrie, exactement comme le protocole ABBA original (prof_mtp_abba.sh).
# Usage : sh repro_16t_cold.sh <out_dir>
OUT="$1"; mkdir -p "$OUT"
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu
PORT=8097

# --- sonde thermique (CPU/SoC réels, plage 30-80 C) ---
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

# --- attendre départ froid < 45 C pour égaler l'historique (42C) ---
i=0
while [ $i -lt 40 ]; do
    T=$(get_temp)
    if [ -n "$T" ] && [ "$T" -le 45000 ] 2>/dev/null; then break; fi
    echo "[WAIT] T=$((T/1000))C — attente départ froid <45C (${i}0s)..."
    sleep 10; i=$((i+1))
done
T_START=$(get_temp)
echo "TEMP_DEPART $((T_START/1000))C"

pkill -f npu/llama-server 2>/dev/null; sleep 1
nohup ./llama-server -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf \
    --spec-type draft-mtp -ngl 99 -t 8 -c 8192 \
    --port $PORT --host 127.0.0.1 > "$OUT/16t_server.log" 2>&1 &
SRV=$!

# wait_ready
i=0
while [ $i -lt 120 ]; do
    curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"' && break
    i=$((i+1)); sleep 2
done

# télémétrie en fond
sh /data/local/tmp/qcmp/prof_telemetry.sh "$OUT/16t_tele.csv" $SRV 120 > /dev/null 2>&1 &
SONDE=$!

# run 16 tokens — avec timestamps SSE précis
echo "=== RUN 16t COLD (départ $((T_START/1000))C) ==="
curl -sN -m 120 "http://127.0.0.1:$PORT/completion" \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"The capital of France is","n_predict":16,"temperature":0,"stream":true}' 2>/dev/null | \
    while IFS= read -r line; do
        echo "$(date +%s.%N) $line" >> "$OUT/16t_stream.txt"
    done
kill $SONDE 2>/dev/null
T_END=$(get_temp)
echo "=== DONE 16t COLD (fin $((T_END/1000))C) ==="

# synthèse
python3 - "$OUT" <<'EOF' 2>/dev/null || true
import re, sys
out = sys.argv[1]
tok_times = {}
first = None
for line in open(out + '/16t_stream.txt', encoding='utf-8', errors='ignore'):
    m = re.match(r'(\d+\.\d+) data:.*"tokens_predicted":(\d+)', line)
    if m:
        t = float(m.group(1)); n = int(m.group(2))
        tok_times[n] = t
        if first is None: first = t
if tok_times:
    nf = max(tok_times)
    wall = tok_times[nf] - first
    tps = nf / wall
    print(f'RESULTAT: tokens={nf} wall={wall:.2f}s tps_emis={tps:.2f}')
log = open(out + '/16t_server.log', encoding='utf-8', errors='ignore').read()
for m in re.finditer(r'draft acceptance = ([0-9.]+) \((\d+) accepted / (\d+) generated\), mean len = ([0-9.]+)', log):
    acc = float(m.group(1)); mean_len = float(m.group(4))
    print(f'MTP: acceptance={acc} mean_len={mean_len}')
    print(f'EFFECTIF (tps_emis × mean_len) = {tps * mean_len:.2f} t/s')
    break
EOF
echo "=== TERMINE ==="