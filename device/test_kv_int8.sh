#!/system/bin/sh
# test_kv_int8.sh — Test KV cache INT8 vs FP16 pour Qwen3.8-9B sur NPU
# Exécuter sur le téléphone : su -c 'sh /data/local/tmp/test_kv_int8.sh'

JZDIR=/data/local/tmp/jz
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
RESULTS=/data/local/tmp/kv_int8_results.txt

export LD_LIBRARY_PATH=$JZDIR/lib:$JZDIR/bin:/vendor/lib64:/data/data/com.termux/files/usr/lib
export ADSP_LIBRARY_PATH=/data/local/tmp
export CDSP_LIBRARY_PATH=/data/local/tmp
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_OPBATCH=1024
export GGML_HEXAGON_OPQUEUE=16
export GGML_HEXAGON_MBUF=3500

BENCH="$JZDIR/bin/llama-bench"
ARGS="-m $MODEL -ngl 99 -t 6 -p 128 -n 32 -r 3 -fa on -lm none -b 128 -ub 16"

echo "================================================================" > $RESULTS
echo "  TEST KV CACHE INT8 vs FP16 — $(date)" >> $RESULTS
echo "================================================================" >> $RESULTS
echo "" >> $RESULTS

# Config 1: FP16 baseline
echo ">>> [1/4] FP16_KV (baseline) -ctk f16 -ctv f16" | tee -a $RESULTS
pkill -9 -f llama-bench 2>/dev/null; sleep 3
$BENCH $ARGS -ctk f16 -ctv f16 2>&1 | grep -E "(pp128|tg32)" | tee -a $RESULTS
echo "" >> $RESULTS

# Config 2: INT8 K+V
echo ">>> [2/4] INT8_KV -ctk q8_0 -ctv q8_0" | tee -a $RESULTS
pkill -9 -f llama-bench 2>/dev/null; sleep 3
$BENCH $ARGS -ctk q8_0 -ctv q8_0 2>&1 | grep -E "(pp128|tg32)" | tee -a $RESULTS
echo "" >> $RESULTS

# Config 3: INT8 K + FP16 V
echo ">>> [3/4] INT8K_FP16V -ctk q8_0 -ctv f16" | tee -a $RESULTS
pkill -9 -f llama-bench 2>/dev/null; sleep 3
$BENCH $ARGS -ctk q8_0 -ctv f16 2>&1 | grep -E "(pp128|tg32)" | tee -a $RESULTS
echo "" >> $RESULTS

# Config 4: FP16 K + INT8 V
echo ">>> [4/4] FP16K_INT8V -ctk f16 -ctv q8_0" | tee -a $RESULTS
pkill -9 -f llama-bench 2>/dev/null; sleep 3
$BENCH $ARGS -ctk f16 -ctv q8_0 2>&1 | grep -E "(pp128|tg32)" | tee -a $RESULTS
echo "" >> $RESULTS

echo "================================================================" >> $RESULTS
echo "DONE — $(date)" >> $RESULTS
echo "Résultats dans $RESULTS"
