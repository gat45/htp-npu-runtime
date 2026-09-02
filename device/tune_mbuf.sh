#!/system/bin/sh
# tune_mbuf.sh — Balayage GGML_HEXAGON_MBUF (3000-3800 MB)
# Exécuter sur le téléphone : su -c 'sh /data/local/tmp/tune_mbuf.sh'

JZDIR=/data/local/tmp/jz
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
RESULTS=/data/local/tmp/mbuf_sweep_results.txt

export LD_LIBRARY_PATH=$JZDIR/lib:$JZDIR/bin:/vendor/lib64:/data/data/com.termux/files/usr/lib
export ADSP_LIBRARY_PATH=/data/local/tmp
export CDSP_LIBRARY_PATH=/data/local/tmp
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_OPBATCH=1024
export GGML_HEXAGON_OPQUEUE=16

BENCH="$JZDIR/bin/llama-bench"
BASE_ARGS="-m $MODEL -ngl 99 -t 6 -p 128 -n 32 -r 3 -fa on -lm none -b 128 -ub 16"

echo "================================================================" > $RESULTS
echo "  MBUF SWEEP — $(date)" >> $RESULTS
echo "  Valeurs testées : 3000 3200 3400 3500 3600 3800 MB" >> $RESULTS
echo "  Runs par valeur : 3 (médiane)" >> $RESULTS
echo "================================================================" >> $RESULTS
echo "" >> $RESULTS

for MBUF in 3000 3200 3400 3500 3600 3800; do
    echo ">>> MBUF=${MBUF} MB" | tee -a $RESULTS
    pkill -9 -f llama-bench 2>/dev/null
    sleep 3

    export GGML_HEXAGON_MBUF=$MBUF
    $BENCH $BASE_ARGS 2>&1 | grep -E "(pp128|tg32)" | tee -a $RESULTS

    echo "" >> $RESULTS
done

echo "================================================================" >> $RESULTS
echo "DONE — $(date)" >> $RESULTS
echo "" >> $RESULTS

# Résumé
echo "=== RÉSUMÉ ===" >> $RESULTS
grep -E "(MBUF=|pp128|tg32)" $RESULTS >> /dev/null

echo "Résultats dans $RESULTS"
