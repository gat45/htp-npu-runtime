#!/system/bin/sh
# MTP + OPPOLL one-shot test — attnQ4 ngl33, upstream 4df29be4f instrumenté
# Draft-mtp = -md <même GGUF> (têtes MTP natives du D2-A-MTP) + --spec-type draft-mtp
export LD_LIBRARY_PATH=/data/local/tmp/instr
export GGML_HEXAGON_OPPOLL=1
export GGML_HEXAGON_OPPOLL_US=500
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
cd /data/local/tmp/instr
echo "=== MTP test: -md same gguf --spec-type draft-mtp ngl33 OPPOLL=1 US=500 ==="
timeout 240 ./llama cli -md "$MODEL" --spec-type draft-mtp -m "$MODEL" -dev HTP0 -ngl 33 \
    -p "Hello" -n 32 -t 8 --no-display-prompt --show-timings -st < /dev/null
echo "RC=$?"
