#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
export QNN_LOG_LEVEL=VERBOSE
export QNN_LOG_FILE=/data/local/tmp/qnn_graph.log
./geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 4 > /data/local/tmp/qnn_run.log 2>&1
echo "EXIT=$?"
grep -aiE "graph|retrieve|binary|context" /data/local/tmp/qnn_graph.log 2>/dev/null | grep -avE "config|kv|seq" | head -10