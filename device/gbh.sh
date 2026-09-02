#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
./geniex-bench --help > /data/local/tmp/gb_help.txt 2>&1
echo "EXIT=$?"
head -40 /data/local/tmp/gb_help.txt