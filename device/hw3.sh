cd /data/local/tmp
LD_LIBRARY_PATH=/data/local/tmp GGML_HEXAGON_VERBOSE=1 timeout 130 ./geniex-bench --plugin llama_cpp --device npu -m /data/local/tmp/qwen05b.gguf --prompt-file /data/local/tmp/prompt.txt -n 8 > /data/local/tmp/hw2.log 2>&1
echo EXIT=$?
grep -aE 'hwinfo|Arch|session|ERROR' /data/local/tmp/hw2.log | head -6