#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
su 10391 -c 'export PATH=/data/data/com.termux/files/usr/bin:$PATH HOME=/data/data/com.termux/files/home PREFIX=/data/data/com.termux/files/usr LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; echo "== pip install geniex (skip sdk) =="; GENIEX_SKIP_SDK_DOWNLOAD=1 pip install geniex 2>&1 | tail -6; echo "== test import + devices =="; GENIEX_LIB_PATH=/data/local/tmp/gxlibs python -c "
from geniex import get_plugin_list, get_device_list
print(\"plugins:\", get_plugin_list())
for p in get_plugin_list():
    try:
        print(p, \"->\", get_device_list(p))
    except Exception as e:
        print(p, \"ERR\", e)
" 2>&1 | head -20'
