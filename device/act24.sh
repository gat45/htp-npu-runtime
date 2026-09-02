#!/system/bin/sh
MODEL8=/data/local/tmp/Qwen3-8B-Q4_K_M.gguf
echo "=== A2: GGML 8B Q4_K_M (meme modele que bundle QAIRT) - JZ HTP0 ==="
cd /data/local/tmp/jz
export LD_LIBRARY_PATH=/data/local/tmp/jz/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/jz/lib
export CDSP_LIBRARY_PATH=/data/local/tmp/jz/lib
export GGML_HEXAGON_NDEV=1 GGML_HEXAGON_MBUF=3400
./bin/llama-bench -m $MODEL8 -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 2>/dev/null | grep -E "pp128|tg16"

echo "=== A4: JZ HOSTBUF ON (9B) ==="
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
export GGML_HEXAGON_HOSTBUF=1
./bin/llama-bench -m $MODEL -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 2>/dev/null | grep -E "tg16"
echo "=== A4: JZ HOSTBUF OFF (9B) ==="
export GGML_HEXAGON_HOSTBUF=0
./bin/llama-bench -m $MODEL -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 2>/dev/null | grep -E "tg16"