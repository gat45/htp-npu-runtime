#!/system/bin/sh
# Test GenieX via ctypes directement sur le device (root)
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/gxlibs/plugins
export GENIEX_LIB_PATH=/data/local/tmp/gxlibs/libgeniex.so
cd /data/local/tmp
echo "== ldd libgeniex.so =="
ldd /data/local/tmp/gxlibs/libgeniex.so 2>&1 | head -30
echo
echo "== diagnostic ctypes =="
python3 /data/local/tmp/geniex_ctypes.py --lib /data/local/tmp/gxlibs/libgeniex.so 2>&1 | head -60
echo "EXIT=$?"
