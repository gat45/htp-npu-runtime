#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/geniex/lib:/data/local/tmp/gxlibs:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/geniex/lib:/data/local/tmp/gxlibs:/data/local/tmp
export GENIEX_SKIP_SDK_DOWNLOAD=1
/data/local/tmp/geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 6