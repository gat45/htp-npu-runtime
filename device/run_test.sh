#!/system/bin/sh
# Test automatisé complet avec monitoring thermique
# Usage: sh run_test.sh <model> <backend> [ts] [tag]
# Vérifie la température avant, lance, vérifie après, bascule si chaud.
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

M="${1:-/data/local/tmp/Qwen3.5-9B-D2-A.gguf}"
BACKEND="${2:-HTP0}"     # HTP0, GPUOpenCL, HTP0,GPUOpenCL
TS="${3:-}"              # tensor-split optionnel (ex: 0.5,0.5)
TAG="${4:-bench}"        # tag pour le log
THRESH=55                # température max pour démarrer
SWITCH=60                # température de bascule

read_gpu_temp() {
  local best=0
  for z in /sys/class/thermal/thermal_zone*; do
    local t=$(cat "$z/type" 2>/dev/null)
    case "$t" in
      gpuss*) local v=$(cat "$z/temp" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$best" ] && best=$v ;;
    esac
  done
  echo $((best/1000))
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1. Vérifier température avant (attendre refroidissement)
log "=== TEST START: $M backend=$BACKEND ts=$TS tag=$TAG ==="
T0=$(read_gpu_temp)
log "Temp initiale: ${T0}C"
if [ "$T0" -ge "$THRESH" ]; then
  log "Device trop chaud (${T0}C >= ${THRESH}C), attente refroidissement..."
  while [ "$(read_gpu_temp)" -ge "$THRESH" ]; do sleep 10; done
  log "Refroidi: $(read_gpu_temp)C"
fi

# 2. Lancer le benchmark
ARGS="-m $M -ngl 99 -p 16 -n 16 -t 8"
if [ -n "$TS" ]; then
  ARGS="$ARGS -sm layer -dev $BACKEND -ts $TS"
else
  ARGS="$ARGS -dev $BACKEND"
fi
LOG="/data/local/tmp/test_${TAG}.log"
log "Lancement: llama-bench $ARGS"
./llama-bench $ARGS > "$LOG" 2>&1
RES=$(grep -E '^\| qwen.*tg16' "$LOG" | tail -1)
log "Résultat tg16: $RES"

# 3. Vérifier température après
T1=$(read_gpu_temp)
log "Temp après: ${T1}C"
if [ "$T1" -ge "$SWITCH" ]; then
  log "Chaud (${T1}C >= ${SWITCH}C) - bascule conseillée vers NPU/GPU"
  log "Recommandation: backend=${BACKEND} -> $([ "$BACKEND" = "HTP0" ] && echo GPUOpenCL || echo HTP0)"
fi

# 4. Résumé
log "=== DONE tag=$TAG result=$RES ==="