#!/system/bin/sh
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/data/local/tmp/gxlibs/llama_cpp:/data/local/tmp/gxlibs/qairt:/data/local/tmp/gxlibs/v0.3:/data/local/tmp/gxlibs/v0.5:/data/local/tmp/npu/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib/rfsa/adsp
export CDSP_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib/rfsa/adsp
export GGML_HEXAGON_NDEV=1
echo "=== AXE2 QAIRT Qwen3-8B W4A16 ==="
/data/data/com.termux/files/usr/bin/python3.14 /data/local/tmp/axe2_qairt_bench.py 2>&1
echo "=== END ==="
