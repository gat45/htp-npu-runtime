#!/system/bin/sh
# ===========================================================================
# RUN HARNESS ÉCO — pour les GROSSES sessions (RAM limitée).
#
#   1. Libère la RAM (apps fermées, caches vidés)
#   2. Lance le harnais avec config_eco.json (contexte réduit 3000 chars,
#      n_threads=2, n_ctx=2048, max_new=512)
#
# Usage :  bash run_harness_eco.sh "ta tâche"
#          (à lancer depuis ~/gx_harness dans Termux)
# ===========================================================================
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export GENIEX_LIB_PATH=/data/local/tmp/gxlibs
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/llama_cpp:/data/local/tmp/qairt:/vendor/lib64:/data/data/com.termux/files/usr/lib

# Réglages Hexagon optimisés (reverse binding OP15)
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_OPBATCH=1024
export GGML_HEXAGON_OPQUEUE=16

TASK="${1:-Donne un aperçu de la situation et propose une action.}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== PRÉPARATION RAM ==="
sh /data/local/tmp/prepare_session.sh 2>/dev/null || echo "(prepare_session.sh absent — continue)"

echo ""
echo "=== LANCEMENT HARNASS (config éco : ctx 2048, threads 2, contexte 3000) ==="
cd "$DIR"
python3 -u harness.py "$TASK" --config config_eco.json --reset
