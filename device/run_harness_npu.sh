#!/data/data/com.termux/files/usr/bin/bash
# ---------------------------------------------------------------------------
# run_harness_npu.sh — lance le harnais AVEC le NPU (HTP0) sur le téléphone.
#
#   bash run_harness_npu.sh "ta tâche"
#
# Exporte les variables nécessaires pour que libgeniex.so charge le backend
# Hexagon (NPU) : sans LD_LIBRARY_PATH incluant /vendor/lib64, le backend
# hexagon ne charge pas (libcdsprpc.so introuvable) et on retombe en CPU.
# ---------------------------------------------------------------------------
set -e
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export GENIEX_LIB_PATH=/data/local/tmp/gxlibs
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/llama_cpp:/data/local/tmp/qairt:/vendor/lib64:/data/data/com.termux/files/usr/lib

# Réglages Hexagon optimisés (issus du reverse binding OP15, llama_jni.cpp) :
#   NDEV=1        : une seule session HTP (NDEV=2 ajoute de la synchro inutile
#                   pour un modèle qui tient dans une session)
#   OPBATCH=1024  : batching d'ops vers le DSP (défaut binding OP15)
#   OPQUEUE=16    : profondeur de queue DSP
#   -> decode 10,2 tok/s vs 8,1 baseline (+26%), prefill 58 vs 40 (+45%)
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_OPBATCH=1024
export GGML_HEXAGON_OPQUEUE=16

export OP15_LLAMA_NTHREADS=8
export OP15_NGPU_LAYERS=24

cd "$(dirname "$0")"
echo "[hôte] NPU: $(geniex-py devices 2>/dev/null | grep -E 'HTP0' | head -1 || echo 'HTP0 non listé — CPU seulement')"
python3 harness.py "$@"
