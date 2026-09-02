#!/system/bin/sh
# =========================================================================
# CONFIG GELÉE — la config qui donne ~16 t/s effectifs (record de la campagne)
#
# Modèle     : Qwen3.5-9B-D2-A-MTP-attnQ4.gguf (5,08 Go, attention re-quantifiée)
# Runtime    : JZ /data/local/tmp/npu (505354ed + AXE-8 + opt_mm_rows)
# Commandes  : -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off
#              --spec-type draft-mtp --spec-draft-n-max 1
#              --host 127.0.0.1 --port <port>   n_predict=16, temperature=0
# Mesures    : wall 9,4-10,4 t/s · mean_len 1,75 · acceptance 75 %
#              EFFECTIFS (formule historique) = wall × mean_len = 16,4-18,9
# Env        : LD_LIBRARY_PATH=ADSP_LIBRARY_PATH=$RUNTIME
#              GGML_HEXAGON_NDEV=1 GGML_HEXAGON_ARCH=v81
# Conditions : départ froid < 45 °C · --fit off (HTP0 ne rapporte pas sa mémoire)
#              kill immédiat post-run · seuil ZRAM 5 Go = stop
#
# Utilise le protocole gardé validé (run_guarded_bench.sh) : kill-all,
# vérif port libre, vérif PID, save meta, kill + vérif clean.
#
# Usage : sh run_16tps_config.sh [n_predict] [label]
# =========================================================================
N="${1:-16}"
LABEL="${2:-q4m1_16tps}"
RUNTIME=/data/local/tmp/npu
OUT=/data/local/tmp/bench_out/16tps
PORT=8540
PROMPT="The capital of France is"

export RUNTIME=$RUNTIME
export OUT=$OUT

# Attente départ froid < 45 °C (zone qmx-0-1 = thermal_zone21 sur ce device)
i=0
while [ $i -lt 60 ]; do
    T=$(cat /sys/class/thermal/thermal_zone21/temp 2>/dev/null)
    case "$T" in ''|*[!0-9]*) T=40000;; esac
    if [ "$T" -le 45000 ] 2>/dev/null; then break; fi
    echo "[WAIT] $((T/1000))C — attente <45C"
    sleep 10; i=$((i+1))
done
echo "TEMP_DEPART $(( $(cat /sys/class/thermal/thermal_zone21/temp 2>/dev/null) / 1000 ))C"

sh "$RUNTIME/run_guarded_bench.sh" "$LABEL" $PORT "$N" "$PROMPT" \
    --spec-type draft-mtp --spec-draft-n-max 1

echo "=== RESULTAT (meta dans $OUT/$LABEL/meta.txt) ==="
cat "$OUT/$LABEL/meta.txt" 2>/dev/null | grep -E "eval time|draft acceptance|T_|label"
echo "DONE — vérif 0 process : $(ps -A | grep llama | grep -v grep | wc -l)"