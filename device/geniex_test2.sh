#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
su 10391 -c 'export PATH=/data/data/com.termux/files/usr/bin:$PATH HOME=/data/data/com.termux/files/home PREFIX=/data/data/com.termux/files/usr LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; GENIEX_LIB_PATH=/data/local/tmp/gxlibs python /data/local/tmp/geniex_test.py 2>&1'
