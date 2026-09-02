#!/system/bin/sh
# Un run de bench par invocation — imprime RESULT puis sort IMMÉDIATEMENT
# (os._exit sans libération -> pas de crash 'Aborted').
# Usage : bench_one.sh <libdir>   (ex: /data/local/tmp/gxlibs)
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export GENIEX_LIB_PATH=$1
export LD_LIBRARY_PATH=$1:/data/local/tmp/llama_cpp:/data/local/tmp/qairt:/vendor/lib64:/data/data/com.termux/files/usr/lib
cd /data/local/tmp

python3 - <<'PYEOF'
import sys, os, json
sys.path.insert(0, "/data/local/tmp")
from geniex_ctypes import GenieX

MODEL = "/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf"
LIB = os.environ.get("GENIEX_LIB_PATH", "/data/local/tmp/gxlibs") + "/libgeniex.so"

gx = GenieX(lib_path=LIB)
llm = gx.create_llm(model_path=MODEL, plugin_id="llama_cpp", device_id="HTP0",
                    n_ctx=0, n_threads=4, n_gpu_layers=-1)
try:
    text, prof = llm.generate("Explique en une phrase ce qu'est un réseau de neurones.", max_tokens=48, temperature=0.7)
    print("RESULT:", json.dumps({
        "decode": prof["decoding_speed"],
        "prefill": prof["prefill_speed"],
        "ttft_ms": prof["ttft_ms"],
        "n_gen": prof["generated_tokens"],
    }), flush=True)
finally:
    os._exit(0)  # sortie immédiate, SANS libération -> pas de crash
PYEOF
echo "EXIT=$?"
