#!/bin/bash
# PROFILE_DECODE.sh — profiling détaillé decode par format
# Usage: adb shell su -c "bash /data/local/tmp/PROFILE_DECODE.sh <model> <format>"
# Exemple: bash PROFILE_DECODE.sh /data/local/tmp/sweep/Qwen3-4B-Q4_0.gguf Q4_0

MODEL="${1:?Usage: $0 <model.gguf> <format>}"
FORMAT="${2:-unknown}"
ADB="C:/Users/videl/AppData/Local/Android/Sdk/platform-tools/adb.exe"
JZ="/data/local/tmp/jz"
NPU="/data/local/tmp/npu"

echo "=== PROFILE DECODE: $FORMAT ==="
echo "Model: $MODEL"
echo "Date: $(date)"
echo ""

# 1. État système AVANT le bench
echo "--- ÉTAT SYSTÈME AVANT ---"
echo "CPU freq:"
for i in 0 4 7; do
  echo -n "  cpu$i: "
  cat /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq 2>/dev/null
done

echo "GPU freq:"
cat /sys/class/devfreq/3d00000.qcom,kgsl-3d0/cur_freq 2>/dev/null || echo "  N/A"

echo "Thermal:"
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print "  zone0: "$1/1000"°C"}'

echo ""

# 2. Run 1: VERBOSE seul (pour compter les batches)
echo "--- RUN 1: VERBOSE (batch counting) ---"
export LD_LIBRARY_PATH=$NPU
export CDSP_LIBRARY_PATH=$NPU
export ADSP_LIBRARY_PATH=$NPU
export GGML_HEXAGON_VERBOSE=1

START=$(date +%s%N)
DATA=$(/data/local/tmp/jz/bin/llama-bench \
  -m "$MODEL" -p 512 -n 32 -r 1 -ngl 99 2>&1)
END=$(date +%s%N)

# Extraire résultats bench
PP=$(echo "$DATA" | grep "pp512" | grep -oP '[0-9.]+ ±' | head -1 | tr -d ' ±')
TG=$(echo "$DATA" | grep "tg32" | grep -oP '[0-9.]+ ±' | head -1 | tr -d ' ±')
WALL=$(( (END - START) / 1000000 ))

echo "PP512: $PP tok/s"
echo "TG32: $TG tok/s"
echo "Wall time: ${WALL}ms"

# Compter les batches
BATCH_COUNT=$(echo "$DATA" | grep -c "op batching" 2>/dev/null)
echo "Batches logged: $BATCH_COUNT"

# Extraire info batches
echo "$DATA" | grep "op batching" | head -5

echo ""

# 3. Run 2: VERBOSE + PROFILE (pour les counters)
echo "--- RUN 2: VERBOSE + PROFILE ---"
export GGML_HEXAGON_VERBOSE=1
export GGML_HEXAGON_PROFILE=1

DATA2=$(/data/local/tmp/jz/bin/llama-bench \
  -m "$MODEL" -p 512 -n 32 -r 1 -ngl 99 2>&1)

echo "$DATA2" | grep -iE "ggml-hex.*profile|pmu|cycle|counter|timing" | head -20

echo ""

# 4. Run 3: simpleperf sur le decode
echo "--- RUN 3: simpleperf (CPU profiling) ---"
# Lancer simpleperf en background pendant le bench
simpleperf stat -e cpu-cycles,instructions,cache-references,cache-misses \
  --duration 10 --interval 1000 \
  /data/local/tmp/jz/bin/llama-bench \
  -m "$MODEL" -p 128 -n 16 -r 1 -ngl 99 2>&1 | head -30

echo ""

# 5. État système APRÈS le bench
echo "--- ÉTAT SYSTÈME APRÈS ---"
echo "CPU freq:"
for i in 0 4 7; do
  echo -n "  cpu$i: "
  cat /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq 2>/dev/null
done

echo "Thermal:"
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print "  zone0: "$1/1000"°C"}'

echo ""
echo "=== RÉSUMÉ $FORMAT ==="
echo "PP512=$PP TG32=$TG Wall=${WALL}ms Batches=$BATCH_COUNT"
