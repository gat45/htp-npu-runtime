#!/bin/bash
# PROFILE_FMT.sh — profiling détaillé decode multi-format
# Usage: adb shell su -c "bash /data/local/tmp/PROFILE_FMT.sh"

NPU="/data/local/tmp/npu"
JZ="/data/local/tmp/jz"
BENCH="$JZ/bin/llama-bench"

# Formats à tester (modèle 9B sauf si spécifié)
declare -A FORMATS
FORMATS=(
  ["Q8_0"]="/data/local/tmp/qwen9b_Q8_0.gguf"
  ["Q5K_B"]="/data/local/tmp/gguf/Qwen3.8-9B-Q5K-MIXED-B.gguf"
  ["Q4_0"]="/data/local/tmp/qwen3.5-9b-pocketpal/qwen3.5-9b-q4_0.gguf"
)

export LD_LIBRARY_PATH=$NPU
export CDSP_LIBRARY_PATH=$NPU
export ADSP_LIBRARY_PATH=$NPU

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PROFILE DECODE — Q8_0 → Q5K → Q4_0 (9B Qwen)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# État système initial
echo "=== SYSTÈME INITIAL ==="
THERMAL=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}')
echo "Thermal: $THERMAL"
echo "CPU0: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null) kHz"
echo ""

for FMT in Q8_0 Q5K_B Q4_0; do
  MODEL="${FORMATS[$FMT]}"
  echo "═══════════════════════════════════════════════════"
  echo "  FORMAT: $FMT"
  echo "  Model: $MODEL"
  echo "═══════════════════════════════════════════════════"
  
  # Taille du fichier
  SIZE=$(ls -lh "$MODEL" 2>/dev/null | awk '{print $5}')
  SIZE_BYTES=$(ls -l "$MODEL" 2>/dev/null | awk '{print $5}')
  echo "Taille: $SIZE ($SIZE_BYTES bytes)"
  
  # ── Run A: Benchmark propre (3 runs) ──
  echo ""
  echo "--- RUN A: Benchmark (3 reps) ---"
  export GGML_HEXAGON_VERBOSE=0
  export GGML_HEXAGON_PROFILE=0
  
  START=$(date +%s%N)
  OUTA=$($BENCH -m "$MODEL" -p 512 -n 32 -r 3 -ngl 99 2>&1)
  END=$(date +%s%N)
  WALL_A=$(( (END - START) / 1000000 ))
  
  PP=$(echo "$OUTA" | grep "pp512" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) print $i}' | head -1)
  TG=$(echo "$OUTA" | grep "tg32" | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) print $i}' | head -1)
  
  echo "PP512: $PP tok/s"
  echo "TG32:  $TG tok/s"
  echo "Wall:  ${WALL_A}ms"
  
  if [ -n "$TG" ] && [ -n "$SIZE_BYTES" ]; then
    BW=$(echo "$SIZE_BYTES $TG" | awk '{printf "%.1f", $1 * $2 / 1073741824}')
    echo "BW effective: ${BW} Go/s"
    MS_TOK=$(echo "$TG" | awk '{printf "%.1f", 1000/$1}')
    echo "ms/token: $MS_TOK"
  fi
  
  # ── Run B: VERBOSE pour batch counting ──
  echo ""
  echo "--- RUN B: VERBOSE (batch counting) ---"
  export GGML_HEXAGON_VERBOSE=1
  export GGML_HEXAGON_PROFILE=0
  
  OUTB=$($BENCH -m "$MODEL" -p 128 -n 16 -r 1 -ngl 99 2>&1)
  
  # Compter les lignes de batching
  BATCH_LINES=$(echo "$OUTB" | grep "op batching" | wc -l)
  echo "Batch log lines: $BATCH_LINES"
  
  # Extraire les stats batches
  echo "$OUTB" | grep "op batching" | head -3
  
  # Compter les flush
  FLUSH_COUNT=$(echo "$OUTB" | grep -c "flush" 2>/dev/null)
  echo "Flush events: $FLUSH_COUNT"
  
  # Extraire VMEM info
  echo "$OUTB" | grep "vmem" | head -3
  
  # ── Run C: simpleperf sur decode ──
  echo ""
  echo "--- RUN C: simpleperf (10s) ---"
  simpleperf stat -e cpu-cycles,instructions,cache-references,cache-misses,branch-misses \
    --duration 10 \
    $BENCH -m "$MODEL" -p 128 -n 16 -r 1 -ngl 99 2>&1 | grep -E "cpu-cycles|instructions|cache|branch|Performance" | head -10
  
  # État thermique
  THERMAL=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f°C", $1/1000}')
  echo ""
  echo "Thermal après: $THERMAL"
  echo ""
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RÉSUMÉ COMPARATIF                                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Format  │ Taille │ TG32   │ BW eff  │ ms/tok │ Batches │ Régime"
echo "────────┼────────┼────────┼─────────┼────────┼─────────┼────────"
echo "Q8_0    │ 9.1 GB │ $TG_Q8 │ ...     │ ...    │ ...     │ ..."
echo "Q5K     │ 5.7 GB │ $TG_Q5 │ ...     │ ...    │ ...     │ ..."
echo "Q4_0    │ 4.9 GB │ $TG_Q4 │ ...     │ ...    │ ...     │ ..."
