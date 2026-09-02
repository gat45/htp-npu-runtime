#!/system/bin/sh
cp /data/local/tmp/geniex/lib/qairt/libgeniex_plugin.so /data/local/tmp/geniex/lib/qairt/libgeniex_plugin.so.bad
cp /data/local/tmp/gxlibs/qairt/libgeniex_plugin.so /data/local/tmp/geniex/lib/qairt/libgeniex_plugin.so
chmod 755 /data/local/tmp/geniex/lib/qairt/libgeniex_plugin.so
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/geniex/lib:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/geniex/lib:/data/local/tmp
export GENIEX_SKIP_SDK_DOWNLOAD=1
echo "=== plugin scan ==="
/data/local/tmp/geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 6 2>&1 | tail -45