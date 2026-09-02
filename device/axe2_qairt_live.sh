#!/system/bin/sh
# axe2_qairt_live.sh — mesure QAIRT live (jambe A du A/B AXE-2) sur Qwen3-8B W4A16.
# Replique exactement la pile T12 qui a fonctionne (geniex-bench natif, root shell).
OUT=/data/local/tmp/axe2_qairt_live.log
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
echo "# pile: geniex-bench natif + libgeniex.so + bundle w4a16 (replique T12)" > "$OUT"
/data/local/tmp/geniex-bench \
    --plugin qairt --device npu \
    -m /data/local/tmp/qwen3-8b-w4a16 \
    -n 256 >> "$OUT" 2>&1
echo "EXIT=$?" >> "$OUT"
