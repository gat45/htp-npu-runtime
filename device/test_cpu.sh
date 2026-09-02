#!/system/bin/sh
cd /data/local/tmp/npu
export LD_LIBRARY_PATH=/data/local/tmp/npu
echo "=== CPU TEST ==="
./llama-cli -m /data/local/tmp/qwen05b.gguf -p Salut -n 32 -t 4 -no-cnv --no-display-prompt 2>&1 | tail -30
echo "=== CPU EXIT: $? ==="
