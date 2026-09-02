#!/system/bin/sh
# rtt_sweep.sh — Mesurer le gap scheduling vs compute HTP
#
# Stratégie: comparer les configurations extrêmes
# A) Batched (32 RTT) = baseline GGML
# B) Monolithique (1 RTT, OPSTAGE=0) = compute pur (mais garbage KV)
# C) CPU seul = référence compute pur sans HTP
#
# Si B >> A → le scheduling est le goulot
# Si B ≈ A → le compute HTP pur est le goulot
#
# Usage: adb shell "su -c 'sh /data/local/tmp/rtt_sweep.sh'"

export LD_LIBRARY_PATH=/data/local/tmp/npu/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/npu/lib
BENCH=/data/local/tmp/npu/llama-bench
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
RESULT=/data/local/tmp/npu/rtt_results.txt

echo "=== RTT SWEEP — $(date) ===" | tee $RESULT
echo "Model: Qwen3.5-9B Q4_0 (5.07 GB)" | tee -a $RESULT
echo "" | tee -a $RESULT

# Kill stale sessions
su -c "killall llama-bench 2>/dev/null; killall llama-cli 2>/dev/null" 2>/dev/null
sleep 3

# ── TEST A: BASELINE (batched, 32 RTT) ──
echo "=== TEST A: BASELINE (batched, ~32 RTT) ===" | tee -a $RESULT
echo "--- r=3, p=512, n=32 ---" | tee -a $RESULT
timeout 180 $BENCH -m $MODEL -p 512 -n 32 -r 3 -ngl 99 --device HTP0 2>&1 | tee -a $RESULT
echo "" | tee -a $RESULT
sleep 5

# ── TEST A2: VERBOSE (capture batch count) ──
echo "=== TEST A2: VERBOSE (capture batch pattern) ===" | tee -a $RESULT
GGML_HEXAGON_VERBOSE=1 timeout 120 $BENCH -m $MODEL -p 512 -n 8 -r 1 -ngl 99 --device HTP0 2>&1 > /data/local/tmp/npu/verbose_A2.txt 2>&1
echo "Saved: verbose_A2.txt" | tee -a $RESULT
# Extract batch info
grep -c "batch #" /data/local/tmp/npu/verbose_A2.txt 2>/dev/null | xargs -I{} echo "Total batches: {}" | tee -a $RESULT
echo "" | tee -a $RESULT
sleep 5

# ── TEST B: MONOLITHIQUE (OPSTAGE=0, 1 RTT, garbled) ──
echo "=== TEST B: MONOLITHIQUE (OPSTAGE=0, 1 RTT) ===" | tee -a $RESULT
echo "--- NOTE: output will be garbled (KV cache bug) ---" | tee -a $RESULT
timeout 120 bash -c 'GGML_HEXAGON_OPSTAGE=0 $BENCH -m $MODEL -p 512 -n 32 -r 1 -ngl 99 --device HTP0 2>&1' | tee -a $RESULT
echo "" | tee -a $RESULT
sleep 5

# ── TEST C: CPU SEUL (référence) ──
echo "=== TEST C: CPU SEUL (8 threads) ===" | tee -a $RESULT
timeout 180 $BENCH -m $MODEL -p 512 -n 32 -r 3 -ngl 0 -t 8 2>&1 | tee -a $RESULT
echo "" | tee -a $RESULT

# ── TEST D: GPU SEUL ──
echo "=== TEST D: GPU OpenCL ===" | tee -a $RESULT
timeout 180 $BENCH -m $MODEL -p 512 -n 32 -r 2 -ngl 99 --device GPUOpenCL 2>&1 | tee -a $RESULT
echo "" | tee -a $RESULT

echo "=== SWEEP COMPLETE ===" | tee -a $RESULT
echo "" | tee -a $RESULT

# ── SUMMARY ──
echo "=== SUMMARY ===" | tee -a $RESULT
grep -E "pp[0-9]+|tg[0-9]+|batch|total|eval" $RESULT 2>/dev/null | tail -30 | tee -a $RESULT
