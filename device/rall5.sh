#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs
for p in part1_of_5.bin part2_of_5.bin part3_of_5.bin part4_of_5.bin part5_of_5.bin; do
  echo "========== $p =========="
  ./qnn_optrace "/data/local/tmp/qwen3-8b-w4a16/$p"
  echo "rc=$?"
done