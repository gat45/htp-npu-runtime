#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs
./qnn_optrace /data/local/tmp/qwen3-8b-w4a16/part1_of_5.bin > /data/local/tmp/optrace_all.txt 2>&1
echo "EXIT=$?"
wc -c /data/local/tmp/optrace_all.txt