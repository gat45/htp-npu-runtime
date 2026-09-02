#!/system/bin/sh
SHIM=/data/local/tmp/libshimqnn.so
adb_none=
# remplacer toutes les copies de libQnnHtp.so par le shim (origines en *_real.so)
for d in /data/local/tmp/gxlibs /data/local/tmp/geniex/lib /data/local/tmp /data/local/tmp/qairt/htp-files; do
  if [ -f "$d/libQnnHtp.so" ] && [ ! -f "$d/libQnnHtp_real.so" ]; then
    cp "$d/libQnnHtp.so" "$d/libQnnHtp_real.so"
  fi
done
cp "$SHIM" /data/local/tmp/gxlibs/libQnnHtp.so
cp "$SHIM" /data/local/tmp/geniex/lib/libQnnHtp.so
cp "$SHIM" /data/local/tmp/libQnnHtp.so
cp "$SHIM" /data/local/tmp/qairt/htp-files/libQnnHtp.so
chmod 755 /data/local/tmp/gxlibs/libQnnHtp.so /data/local/tmp/geniex/lib/libQnnHtp.so /data/local/tmp/libQnnHtp.so /data/local/tmp/qairt/htp-files/libQnnHtp.so
echo "copies remplacees:"
ls -la /data/local/tmp/gxlibs/libQnnHtp.so /data/local/tmp/geniex/lib/libQnnHtp.so /data/local/tmp/libQnnHtp.so /data/local/tmp/qairt/htp-files/libQnnHtp.so
rm -f /data/local/tmp/qnn_shim.log
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/geniex/lib:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/geniex/lib:/data/local/tmp
export GENIEX_SKIP_SDK_DOWNLOAD=1
echo "=== bench ==="
/data/local/tmp/geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 3 2>&1 | tail -3
echo "=== SHIM LOG ==="
wc -l /data/local/tmp/qnn_shim.log 2>/dev/null