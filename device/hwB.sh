am force-stop com.op15.toolkit; am force-stop com.op15.toolkit.scout; sleep 3
cd /data/local/tmp
LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/llama_cpp:/data/local/tmp/qairt timeout 130 ./geniex-bench --plugin llama_cpp --device npu -m /data/local/tmp/qwen05b.gguf --prompt-file /data/local/tmp/prompt.txt -n 8 > /data/local/tmp/hwA.log 2>&1
echo EXIT=$?
grep -aE 'hwinfo|new session :|prefill_tps|decode_tps|0x80000406' /data/local/tmp/hwA.log | head -8