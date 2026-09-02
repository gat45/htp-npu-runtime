#!/system/bin/sh
# ===========================================================================
# NPU PROFILE — balaie n_gpu_layers sur HTP0, un sous-process par run.
# Parse les metriques depuis le log TRACE du runtime (le crash post-generate
# empeche Python de retourner son JSON). Egalement n_threads + ctx.
# Usage : sh npu_profile.sh <libdir> <model> <ngls_csv> [runs] [n_ctx] [n_threads]
#   ex  : sh npu_profile.sh /data/local/tmp/gxlibs \
#             /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf \
#             "0,8,16,24,32,-1" 2 4096 4
# ===========================================================================
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
LIBDIR=$1
MODEL=$2
NGLS=$3
RUNS=${4:-2}
NCTX=${5:-4096}
NTHREADS=${6:-4}
export GENIEX_LIB_PATH=$LIBDIR
export LD_LIBRARY_PATH=$LIBDIR:/data/local/tmp/llama_cpp:/data/local/tmp/qairt:/vendor/lib64:/data/data/com.termux/files/usr/lib
WORK=/data/data/com.termux/files/home
OUT=$WORK/npu_profile.json
cd $WORK

parse_trace() {
  LOG=$1
  DECODE=$(grep -o "decoding_speed: [0-9.]*" "$LOG" 2>/dev/null | tail -1 | awk '{print $2}')
  PREFILL=$(grep -o "prefill_speed: [0-9.]*" "$LOG" 2>/dev/null | tail -1 | awk '{print $2}')
  TTFT=$(grep -o "ttft: [0-9]*" "$LOG" 2>/dev/null | tail -1 | awk '{print $2}')
  GEN=$(grep -o "generated_tokens: [0-9]*" "$LOG" 2>/dev/null | tail -1 | awk '{print $2}')
  STOP=$(grep -o "stop_reason: [a-z]*" "$LOG" 2>/dev/null | tail -1 | awk '{print $2}')
  echo "{\"decode_tps\": ${DECODE:-null}, \"prefill_tps\": ${PREFILL:-null}, \"ttft_us\": ${TTFT:-null}, \"n_gen\": ${GEN:-null}, \"stop\": \"${STOP:-?}\"}"
}

echo "{" > $OUT
echo "  \"libdir\": \"$LIBDIR\"," >> $OUT
echo "  \"model\": \"$MODEL\"," >> $OUT
echo "  \"runs_per_ngl\": $RUNS," >> $OUT
echo "  \"n_ctx\": $NCTX," >> $OUT
echo "  \"n_threads\": $NTHREADS," >> $OUT
echo "  \"results\": [" >> $OUT

FIRST=1
for NGL in $(echo "$NGLS" | tr ',' ' '); do
  for R in $(seq 1 $RUNS); do
    MEM_BEFORE=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    RUNLOG=$WORK/npu_run_${NGL}_${R}.log
    echo "--- ngl=$NGL run=$R ---" > $RUNLOG
    GENIEX_LIB_PATH=$LIBDIR python3 /data/local/tmp/npu_probe.py "$MODEL" "$NGL" "$NCTX" 16 "$NTHREADS" >> $RUNLOG 2>&1
    RESULT=$(parse_trace $RUNLOG)
    MEM_AFTER=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    if [ "$FIRST" -eq 1 ]; then FIRST=0; else echo "," >> $OUT; fi
    echo "    {\"ngl\": $NGL, \"run\": $R, \"mem_free_kb_before\": $MEM_BEFORE, \"mem_free_kb_after\": $MEM_AFTER, \"result\": $RESULT}" >> $OUT
    echo "ngl=$NGL run=$R : $RESULT"
  done
done
echo "  ]" >> $OUT
echo "}" >> $OUT
echo "DONE"
