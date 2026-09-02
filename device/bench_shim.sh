#!/system/bin/sh
rm -f /data/local/tmp/qnn_shim.log
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/geniex/lib:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/geniex/lib:/data/local/tmp
export GENIEX_SKIP_SDK_DOWNLOAD=1
export LD_PRELOAD=/data/local/tmp/libshimqnn.so
/data/local/tmp/geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 4 2>&1 | tail -6
echo "=== SHIM LOG ==="
wc -l /data/local/tmp/qnn_shim.log