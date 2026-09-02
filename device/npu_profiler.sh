#!/system/bin/sh
# ===========================================================================
# NPU PROFILER — adapté de d2_slow_layer_profiler.py au Snapdragon HTP.
#
# Balaye n_gpu_layers (0 → -1) sur le device HTP0 avec un VRAI prompt (pas de
# tokens aléatoires, inadaptés au SSM), mesure decode/prefill/TTFT/RAM par
# config, et écrit un rapport JSON exploitable. Un sous-process par config
# (os._exit → pas de crash 'Aborted' à la libération).
#
# Usage :  sh npu_profiler.sh <libdir> <model> <ngl:liste> [runs]
#   ex :   sh npu_profiler.sh /data/local/tmp/gxlibs \
#              /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf "0,8,16,24,32,-1" 2
# ===========================================================================
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
LIBDIR=$1
MODEL=$2
NGLS=$3
RUNS=${4:-2}
export GENIEX_LIB_PATH=$LIBDIR
export LD_LIBRARY_PATH=$LIBDIR:/data/local/tmp/llama_cpp:/data/local/tmp/qairt:/vendor/lib64:/data/data/com.termux/files/usr/lib
OUT=/data/local/tmp/npu_profile.json
cd /data/local/tmp

echo "{" > $OUT
echo "  \"libdir\": \"$LIBDIR\"," >> $OUT
echo "  \"model\": \"$MODEL\"," >> $OUT
echo "  \"runs_per_ngl\": $RUNS," >> $OUT
echo "  \"results\": [" >> $OUT

FIRST=1
for NGL in $(echo "$NGLS" | tr ',' ' '); do
  for R in $(seq 1 $RUNS); do
    MEM_BEFORE=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    RESULT=$(GENIEX_LIB_PATH=$LIBDIR python3 - "$MODEL" "$NGL" 2>/dev/null <<'PYEOF' || echo "{}"
import sys, os, json
sys.path.insert(0, "/data/local/tmp")
from geniex_ctypes import GenieX
model, ngl = sys.argv[1], int(sys.argv[2])
gx = GenieX(lib_path=os.environ["GENIEX_LIB_PATH"] + "/libgeniex.so")
llm = gx.create_llm(model_path=model, plugin_id="llama_cpp", device_id="HTP0",
                    n_ctx=0, n_threads=4, n_gpu_layers=ngl)
try:
    text, prof = llm.generate("Explique en une phrase ce qu'est un reseau de neurones.", max_tokens=48, temperature=0.7)
    print(json.dumps({
        "ngl": ngl,
        "decode_tps": round(prof["decoding_speed"], 2),
        "prefill_tps": round(prof["prefill_speed"], 2),
        "ttft_ms": round(prof["ttft_ms"], 1),
        "n_gen": prof["generated_tokens"],
        "stop": prof["stop_reason"],
    }), flush=True)
finally:
    os._exit(0)
PYEOF
)
    MEM_AFTER=$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    if [ "$FIRST" -eq 1 ]; then FIRST=0; else echo "," >> $OUT; fi
    echo "    {\"ngl\": $NGL, \"run\": $R, \"mem_free_mb_before\": $MEM_BEFORE, \"mem_free_mb_after\": $MEM_AFTER, \"result\": $RESULT}" >> $OUT
    echo "ngl=$NGL run=$R : $RESULT  (mem avant=$MEM_BEFORE kB, apres=$MEM_AFTER kB)"
  done
done

echo "  ]" >> $OUT
echo "}" >> $OUT
echo "DONE -> $OUT"
