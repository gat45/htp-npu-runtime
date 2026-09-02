#!/system/bin/sh
# htp_attention_bench.sh — bench du fix « couches attention -> HTP0 ».
# IMPORTANT : lancé en USER SHELL (pas su -c) — le 0x80000406 n'apparaît
# qu'en root (RAG doc 64190 / RAPPORT_RESOLUTION_SKEL_HANG).
# Usage (user shell) :
#   adb shell "cd /data/local/tmp && sh htp_attention_bench.sh"
OUT=/data/local/tmp/htp_attention.log
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
cd /data/local/tmp/npu || exit 2
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp CDSP_LIBRARY_PATH=/data/local/tmp
export GGML_HEXAGON_NDEV=1 GGML_HEXAGON_MBUF=3400
PATTERN='blk\.(3|7|11|15|19|23|27|31)\..*'

echo "=== HTP ATTENTION FORCE — $(date) ===" > "$OUT"
echo "device list:" >> "$OUT"
./llama-bench --list-devices >> "$OUT" 2>&1

echo "" >> "$OUT"
echo "=== [1/3] BASELINE (split defaut, tout OpenCL) ===" >> "$OUT"
timeout 240 ./llama-bench -m "$MODEL" -ngl 99 -p 64 -n 16 -r 1 \
    -dev GPUOpenCL,HTP0 >> "$OUT" 2>&1
echo "BASELINE_EXIT=$?" >> "$OUT"

echo "" >> "$OUT"
echo "=== [2/3] FIX : attention -> HTP0 (-ot) ===" >> "$OUT"
timeout 240 ./llama-bench -m "$MODEL" -ngl 99 -p 64 -n 16 -r 1 \
    -dev GPUOpenCL,HTP0 -ot "$PATTERN=HTP0" >> "$OUT" 2>&1
echo "FIX_EXIT=$?" >> "$OUT"

echo "" >> "$OUT"
echo "=== [3/3] VERIF assignment verbose (charge courte) ===" >> "$OUT"
GGML_HEXAGON_VERBOSE=1 timeout 60 ./llama-bench -m "$MODEL" -ngl 99 \
    -p 8 -n 1 -r 1 -dev GPUOpenCL,HTP0 -ot "$PATTERN=HTP0" \
    >> "$OUT" 2>&1
echo "VERIFY_EXIT=$?" >> "$OUT"

echo "" >> "$OUT"
echo "=== DONE $(date) ===" >> "$OUT"
