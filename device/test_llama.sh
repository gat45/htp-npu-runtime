#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/llama_cpp
cd /data/local/tmp/llama_cpp
echo "=== llama-server --help (head) ==="
./llama-server --help 2>&1 | head -25
echo "=== EXIT ==="
