#!/system/bin/sh
# ===========================================================================
# FULL JZ BENCH — prepare_session + confirmation JZ record en un seul script.
#
# Étapes :
#   1. Libère la RAM (apps fermées, caches vidés)
#   2. Affiche l'état mémoire
#   3. Lance llama-bench (PP/TG, 3 runs) avec le backend JZ
#   4. Lance llama-cli (prompt réel, 3 runs) avec le backend JZ
#   5. Résumé final
#
# Usage (depuis le PC via adb) :
#   sh full_jz_bench.sh [runs]
#
# Ou directement sur le téléphone :
#   su -c 'sh /data/local/tmp/full_jz_bench.sh 3'
# ===========================================================================

RUNS=${1:-3}
JZDIR=/data/local/tmp/jz
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
OUT=/data/local/tmp/jz_full_bench_results.txt

# ── Env vars JZ ──────────────────────────────────────────────────────────
export LD_LIBRARY_PATH=$JZDIR/lib:$JZDIR/bin:/vendor/lib64:/data/data/com.termux/files/usr/lib
export ADSP_LIBRARY_PATH=/data/local/tmp
export CDSP_LIBRARY_PATH=/data/local/tmp
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_OPBATCH=1024
export GGML_HEXAGON_OPQUEUE=16
export GGML_HEXAGON_MBUF=3500

# ── Helpers ──────────────────────────────────────────────────────────────
sep() { echo ""; echo "================================================================"; echo "  $1"; echo "================================================================"; echo ""; }
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# ── Vérifications ────────────────────────────────────────────────────────
if [ ! -f "$JZDIR/bin/llama-bench" ]; then
    echo "ERREUR: llama-bench introuvable dans $JZDIR/bin/"
    echo "       Déployez d'abord le backend JZ"
    exit 1
fi
if [ ! -f "$MODEL" ]; then
    echo "ERREUR: Modèle introuvable : $MODEL"
    exit 1
fi

echo "" > $OUT
echo "================================================================" >> $OUT
echo "  FULL JZ BENCH — $(timestamp)" >> $OUT
echo "  Model: $MODEL" >> $OUT
echo "  Runs: $RUNS" >> $OUT
echo "================================================================" >> $OUT

# ══════════════════════════════════════════════════════════════════════════
# PHASE 0 : PREPARE SESSION
# ══════════════════════════════════════════════════════════════════════════
sep "PHASE 0 : PRÉPARATION RAM"

echo "  [0.1] Mémoire AVANT :"
awk '/MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree/ {printf "    %s = %.2f Go\n", $1, $2/1048576}' /proc/meminfo
echo ""

echo "  [0.2] Fermeture des apps..."
am kill-all 2>/dev/null
for pkg in \
  com.android.chrome com.google.android.youtube com.google.android.apps.maps \
  com.google.android.gm com.oneplus.gallery com.oplus.gallery com.oplus.camera \
  com.facebook.katana com.instagram.android com.whatsapp com.tencent.mm \
  com.op15.toolkit.scout io.github.rabehx.securify com.pocketpalai; do
  pm path "$pkg" >/dev/null 2>&1 && { am force-stop "$pkg" 2>/dev/null && echo "    fermé: $pkg"; }
done

echo ""
echo "  [0.3] Vidage des caches..."
sync 2>/dev/null
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && echo "    drop_caches OK" || echo "    drop_caches refusé"
echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null

echo ""
echo "  [0.4] Attente stabilisation (3s)..."
sleep 3

echo ""
echo "  [0.5] Mémoire APRÈS :"
awk '/MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree/ {printf "    %s = %.2f Go\n", $1, $2/1048576}' /proc/meminfo
MEM_AVAIL=$(awk '/MemAvailable/ {printf "%.2f", $2/1048576}' /proc/meminfo)
echo ""
echo "    RAM disponible : ${MEM_AVAIL} Go"
echo "" >> $OUT
echo "RAM available: ${MEM_AVAIL} Go" >> $OUT

# Vérification RAM
MEM_INT=$(echo "$MEM_AVAIL" | awk '{printf "%d", $1 * 1000}')
if [ "$MEM_INT" -lt 4000 ]; then
    echo ""
    echo "  ⚠️  ATTENTION : RAM < 4 Go (modèle 9B = ~5.5 Go)"
    echo "     Le chargement pourrait échouer ou provoquer des swappages."
    echo ""
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 1 : LLAMA-BENCH (PP + TG, 3 runs)
# ══════════════════════════════════════════════════════════════════════════
sep "PHASE 1 : LLAMA-BENCH (PP128 + TG32, ${RUNS} runs)"

BENCH_START=$(date +%s)

timeout 600 $JZDIR/bin/llama-bench \
  -m "$MODEL" \
  -ngl 99 \
  -t 6 \
  -p 128 \
  -n 32 \
  -r $RUNS \
  -lm none \
  -fa on \
  -b 128 \
  -ub 16 \
  2>&1 | tee -a $OUT

BENCH_END=$(date +%s)
BENCH_ELAPSED=$((BENCH_END - BENCH_START))
echo "" >> $OUT
echo "Bench elapsed: ${BENCH_ELAPSED}s" >> $OUT

# ══════════════════════════════════════════════════════════════════════════
# PHASE 2 : LLAMA-CLI (prompt réel, ${RUNS} runs)
# ══════════════════════════════════════════════════════════════════════════
sep "PHASE 2 : LLAMA-CLI (prompt réel, ${RUNS} runs)"

# ── Note : llama-cli JZ n'est pas utilisable (libllama-cli-impl.so absente)
# Seul llama-bench fonctionne avec le build JZ actuel.
# Les résultats TG de llama-bench correspondent au decode token-generate.
echo ""
echo "  ℹ️  llama-cli JZ non disponible (libllama-cli-impl.so absente)"
echo "  → Résultats basés sur llama-bench uniquement"
echo "" >> $OUT
echo "Note: llama-cli JZ unavailable, using llama-bench only" >> $OUT

# ══════════════════════════════════════════════════════════════════════════
# PHASE 3 : RÉSUMÉ
# ══════════════════════════════════════════════════════════════════════════
sep "RÉSUMÉ FINAL"

TOTAL_START=$(date +%s)
echo "" >> $OUT
echo "Total elapsed: $((TOTAL_START - BENCH_START))s" >> $OUT

echo "  📊 Résultats écrits dans : $OUT"
echo ""
echo "  Pour récupérer le rapport :"
echo "    adb pull $OUT ./jz_full_bench_results.txt"
echo ""
echo "  Commande JZ complète :"
echo "    $JZDIR/bin/llama-bench -m $MODEL -ngl 99 -t 6 -p 128 -n 32 -r $RUNS -lm none -fa on -b 128 -ub 16"
echo ""
echo "  LD_LIBRARY_PATH (SANS gxlibs !) :"
echo "    $LD_LIBRARY_PATH"
echo ""
echo "  GGML_HEXAGON_MBUF=$GGML_HEXAGON_MBUF"
echo ""
echo "DONE — $(timestamp)"
