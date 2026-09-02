#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
./geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 32 2>&1
