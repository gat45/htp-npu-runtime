#!/system/bin/sh
# PROFILE_SMMU_LATENCY.sh — Capture ftrace pendant bench 9B, mesure Δt map_pages
# Usage: adb push PROFILE_SMMU_LATENCY.sh /data/local/tmp/ && adb shell "su -c 'sh /data/local/tmp/PROFILE_SMMU_LATENCY.sh'"

set -e

DEVICE_DIR="/data/local/tmp"
LIB_DIR="${DEVICE_DIR}/npu"
BENCH="${DEVICE_DIR}/npu/llama-bench"
MODEL="${DEVICE_DIR}/models/sweep/Qwen3.5-9B-Q4_0.gguf"
FTRACE_DIR="/sys/kernel/tracing"
RESULT_DIR="${DEVICE_DIR}/bench_results"

mkdir -p "$RESULT_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PROFILE SMMU LATENCY — mesures Δt entre map_pages events  ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# 1. Configurer l'environnement
export LD_LIBRARY_PATH="${LIB_DIR}:${DEVICE_DIR}"
export ADSP_LIBRARY_PATH="${LIB_DIR}"
export CDSP_LIBRARY_PATH="${LIB_DIR}"

# 2. Vérifier la paire HOST/SKEL
echo ""
echo "=== PAIRE HOST/SKEL ==="
HOST_MD5=$(md5sum "$LIB_DIR/libggml-hexagon.so" 2>/dev/null | cut -d' ' -f1)
SKEL_MD5=$(md5sum "$LIB_DIR/libggml-htp-v81.so" 2>/dev/null | cut -d' ' -f1)
echo "Host: $HOST_MD5"
echo "Skel: $SKEL_MD5"

# 3. Arrêter ftrace existant
echo 0 > "$FTRACE_DIR/tracing_on" 2>/dev/null || true
echo "" > "$FTRACE_DIR/trace" 2>/dev/null || true

# 4. Augmenter la taille du buffer (128 Mo pour capturer suffisamment)
echo 131072 > "$FTRACE_DIR/buffer_size_kb" 2>/dev/null || echo "buffer_size_kb set failed (non-fatal)"

# 5. Activer les events arm_smmu + fastrpc
echo 1 > "$FTRACE_DIR/events/arm_smmu/map_pages/enable" 2>/dev/null || echo "map_pages enable failed"
echo 1 > "$FTRACE_DIR/events/arm_smmu/unmap_pages/enable" 2>/dev/null || echo "unmap_pages enable failed"
echo 1 > "$FTRACE_DIR/events/arm_smmu/tlbi_start/enable" 2>/dev/null || echo "tlbi_start enable failed"
echo 1 > "$FTRACE_DIR/events/arm_smmu/tlbi_end/enable" 2>/dev/null || echo "tlbi_end enable failed"
echo 1 > "$FTRACE_DIR/events/fastrpc/fastrpc_context_alloc/enable" 2>/dev/null || echo "context_alloc enable failed"
echo 1 > "$FTRACE_DIR/events/fastrpc/fastrpc_context_free/enable" 2>/dev/null || echo "context_free enable failed"
echo 1 > "$FTRACE_DIR/events/fastrpc/fastrpc_context_complete/enable" 2>/dev/null || echo "context_complete enable failed"
echo 1 > "$FTRACE_DIR/events/fastrpc/fastrpc_dspsignal/enable" 2>/dev/null || echo "dspsignal enable failed"
echo 1 > "$FTRACE_DIR/events/fastrpc/fastrpc_transport_response/enable" 2>/dev/null || echo "transport_response enable failed"

# 6. État initial du buffer
echo ""
echo "=== FTRACE BUFFER STATE ==="
echo "buffer_size_kb: $(cat $FTRACE_DIR/buffer_size_kb 2>/dev/null)"
echo "events enabled:"
echo "  arm_smmu/map_pages: $(cat $FTRACE_DIR/events/arm_smmu/map_pages/enable 2>/dev/null)"
echo "  arm_smmu/unmap_pages: $(cat $FTRACE_DIR/events/arm_smmu/unmap_pages/enable 2>/dev/null)"
echo "  fastrpc/context_alloc: $(cat $FTRACE_DIR/events/fastrpc/fastrpc_context_alloc/enable 2>/dev/null)"

# 7. Vider le buffer
echo "" > "$FTRACE_DIR/trace"

# 8. Démarrer ftrace
echo 1 > "$FTRACE_DIR/tracing_on"

echo ""
echo "=== FTRACE STARTED — lancement du bench ==="
echo "Timestamp: $(date)"

# 9. Lancer le bench (3 runs pour avoir assez de données, -n 32 tokens)
$BENCH -m "$MODEL" -ngl 99 -t 8 -n 32 -r 3 \
  -e "ggml-hex" \
  --device HTP0 \
  2>&1 | tee "$RESULT_DIR/smmu_bench_output.txt"

BENCH_EXIT=$?

echo ""
echo "=== BENCH DONE (exit=$BENCH_EXIT) — arrêt ftrace ==="

# 10. Arrêter ftrace
echo 0 > "$FTRACE_DIR/tracing_on"

# 11. Sauvegarder le trace brut
echo "=== SAVING TRACE ==="
TRACE_SIZE=$(wc -c < "$FTRACE_DIR/trace" 2>/dev/null || echo "0")
echo "Trace size: $TRACE_SIZE bytes"

# Copier le trace complet
cp "$FTRACE_DIR/trace" "$RESULT_DIR/smmu_ftrace_full.txt" 2>/dev/null || true

# 12. Filtrer les events map_pages avec timestamps
echo "=== FILTERING map_pages EVENTS ==="
grep -E "map_pages|unmap_pages" "$RESULT_DIR/smmu_ftrace_full.txt" > "$RESULT_DIR/smmu_map_pages_only.txt" 2>/dev/null || true
MAP_COUNT=$(wc -l < "$RESULT_DIR/smmu_map_pages_only.txt" 2>/dev/null || echo "0")
echo "map_pages + unmap_pages events: $MAP_COUNT"

# 13. Filtrer les events fastrpc
grep -E "fastrpc_context_alloc|fastrpc_context_free|fastrpc_context_complete|fastrpc_dspsignal|fastrpc_transport" "$RESULT_DIR/smmu_ftrace_full.txt" > "$RESULT_DIR/smmu_fastrpc_only.txt" 2>/dev/null || true
FASTRPC_COUNT=$(wc -l < "$RESULT_DIR/smmu_fastrpc_only.txt" 2>/dev/null || echo "0")
echo "fastrpc events: $FASTRPC_COUNT"

# 14. Afficher un extrait (premiers et derniers events)
echo ""
echo "=== PREMIERS 10 EVENTS map_pages ==="
head -10 "$RESULT_DIR/smmu_map_pages_only.txt" 2>/dev/null

echo ""
echo "=== DERNIERS 10 EVENTS map_pages ==="
tail -10 "$RESULT_DIR/smmu_map_pages_only.txt" 2>/dev/null

# 15. Extraire les timestamps et calculer les Δt (premiers 100)
echo ""
echo "=== CALCUL Δt ENTRE map_pages CONSÉCUTIFS ==="
echo "Fichier complet: $RESULT_DIR/smmu_map_pages_only.txt"
echo "Le script Python d2_trace_analyze.py sera utilisé pour le calcul détaillé"

# 16. Résumé des compteurs
echo ""
echo "=== RÉSUMÉ COMPTAGE ==="
MAP_FULL=$(grep -c "map_pages" "$RESULT_DIR/smmu_map_pages_only.txt" 2>/dev/null || echo "0")
UNMAP_FULL=$(grep -c "unmap_pages" "$RESULT_DIR/smmu_map_pages_only.txt" 2>/dev/null || echo "0")
CONTEXT_ALLOC=$(grep -c "fastrpc_context_alloc" "$RESULT_DIR/smmu_fastrpc_only.txt" 2>/dev/null || echo "0")
CONTEXT_FREE=$(grep -c "fastrpc_context_free" "$RESULT_DIR/smmu_fastrpc_only.txt" 2>/dev/null || echo "0")
DSPSIGNAL=$(grep -c "fastrpc_dspsignal" "$RESULT_DIR/smmu_fastrpc_only.txt" 2>/dev/null || echo "0")
TRANSPORT_RESP=$(grep -c "fastrpc_transport_response" "$RESULT_DIR/smmu_fastrpc_only.txt" 2>/dev/null || echo "0")

echo "map_pages:      $MAP_FULL"
echo "unmap_pages:    $UNMAP_FULL"
echo "context_alloc:  $CONTEXT_ALLOC"
echo "context_free:   $CONTEXT_FREE"
echo "dspsignal:      $DSPSIGNAL"
echo "transport_resp: $TRANSPORT_RESP"

# 17. Désactiver les events
echo 0 > "$FTRACE_DIR/events/arm_smmu/map_pages/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/arm_smmu/unmap_pages/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/arm_smmu/tlbi_start/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/arm_smmu/tlbi_end/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/fastrpc/fastrpc_context_alloc/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/fastrpc/fastrpc_context_free/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/fastrpc/fastrpc_context_complete/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/fastrpc/fastrpc_dspsignal/enable" 2>/dev/null
echo 0 > "$FTRACE_DIR/events/fastrpc/fastrpc_transport_response/enable" 2>/dev/null

echo ""
echo "=== DONE ==="
echo "Fichiers dans $RESULT_DIR:"
ls -la "$RESULT_DIR"/smmu_*
