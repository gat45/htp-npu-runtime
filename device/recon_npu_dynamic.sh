#!/system/bin/sh
# recon_npu_dynamic.sh — Test dynamique NPU : idle → inference → arrêt
#
# Objectif (doc 2026-08-19, section 15/19/20) : produire une série temporelle
# corrélée de l'activité NSP/HTP pendant une charge réelle :
#
#   idle → inference → inference continue → arrêt
#
# avec, en parallèle :
#   - température nsphvx*/nsphmx* (NSP) + gpuss* (GPU) + CPU
#   - logcat (grep htp|hexagon|qnn|fastrpc|nsp|cdsp|backend|genie)
#   - dmesg (kernel : fastrpc, remoteproc)
#   - BW interconnect (bw_hwmon_meas si exposé)
#
# Usage : su -c 'sh /data/local/tmp/recon_npu_dynamic.sh'
#
# Variables ajustables (avant exécution) :
#   CHARGE_CMD  : commande de charge à lancer entre idle et arrêt.
#                 Par défaut : llama-bench/llama-cli s'ils existent sur le
#                 device, sinon une boucle CPU (test de méthode).
#   CHARGE_SEC  : durée de la phase de charge (défaut 60 s).
#   IDLE_SEC    : durée de la phase idle avant/après (défaut 15 s).

set -u
OUT=/data/local/tmp/npu_recon
mkdir -p "$OUT"
IDLE_SEC=${IDLE_SEC:-15}
CHARGE_SEC=${CHARGE_SEC:-60}

LLAMA_BENCH=$(ls /data/local/tmp/llama-bench 2>/dev/null || echo "")
LLAMA_CLI=$(ls /data/local/tmp/llama-cli 2>/dev/null || echo "")
GGUF=$(ls /data/local/tmp/qwen05b.gguf /data/local/tmp/models/*.gguf 2>/dev/null | head -1)

if [ -n "$LLAMA_BENCH" ] && [ -n "$GGUF" ]; then
  CHARGE_CMD="/data/local/tmp/llama-bench -m $GGUF -n 64 -t 4"
elif [ -n "$LLAMA_CLI" ] && [ -n "$GGUF" ]; then
  CHARGE_CMD="/data/local/tmp/llama-cli -m $GGUF -p test -n 64"
else
  echo "[recon] aucun llama-bench/cli+gguf trouvé -> charge CPU de secours (méthode)"
  CHARGE_CMD="for i in 1 2 3 4; do (while :; do :; done) & done"
fi

logfile="$OUT/dynamic_series.txt"
> "$logfile"

sample() {
  date +%s%3N
  for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      nsphvx*|nsphmx*|gpuss*|cpuss*) printf "%s=%s " "$t" "$(cat "$z/temp" 2>/dev/null)";;
    esac
  done
  echo
}

echo "[recon] test dynamique — idle ${IDLE_SEC}s, charge ${CHARGE_SEC}s"
echo "[recon] commande de charge : $CHARGE_CMD"
echo "[recon] série temporelle -> $logfile"

# 0. pré-capture logcat/dmesg (vide le buffer)
logcat -c 2>/dev/null
dmesg -c >/dev/null 2>&1

# 1. idle
echo "=== PHASE idle (avant) ==="
for i in $(seq 1 "$IDLE_SEC"); do sample; sleep 1; done

# 2. charge
echo "=== PHASE charge ($CHARGE_SEC s) ==="
sh -c "$CHARGE_CMD" >/dev/null 2>&1 &
CPID=$!
for i in $(seq 1 "$CHARGE_SEC"); do sample; sleep 1; done

# 3. arrêt de la charge
echo "=== ARRET charge ==="
kill $CPID 2>/dev/null
sleep 1
kill -9 $CPID 2>/dev/null
pkill -f llama-bench 2>/dev/null
pkill -f llama-cli 2>/dev/null

# 4. idle (après)
echo "=== PHASE idle (après) ==="
for i in $(seq 1 "$IDLE_SEC"); do sample; sleep 1; done

# 5. captures corrélées
echo "=== logcat (filtre NPU) ==="
logcat -d 2>/dev/null | grep -Ei 'htp|hexagon|qnn|fastrpc|nsp|cdsp|backend|genie|ggml' \
  | tail -80 > "$OUT/dynamic_logcat.txt" 2>&1
echo "=== dmesg (filtre fastrpc/rproc) ==="
dmesg 2>/dev/null | grep -Ei 'fastrpc|remoteproc|glink' \
  | tail -60 > "$OUT/dynamic_dmesg.txt" 2>&1

echo "[recon] terminé :"
ls -la "$OUT" | grep dynamic
