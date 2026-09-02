cd /data/local/tmp
nohup sh -c 'LD_LIBRARY_PATH=/data/local/tmp GGML_HEXAGON_VERBOSE=1 ./geniex-bench --plugin llama_cpp --device npu -m /data/local/tmp/qwen05b.gguf --prompt-file /data/local/tmp/prompt.txt -n 8 > /data/local/tmp/hwinfo_run.log 2>&1' >/dev/null 2>&1 &
echo lance