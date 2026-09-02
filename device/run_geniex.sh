#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64:/vendor/dsp/cdsp
export ADSP_LIBRARY_PATH=/vendor/dsp/adsp
export CDSP_LIBRARY_PATH=/vendor/dsp/cdsp
export GENIEX_LOG_LEVEL=trace
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
TOK=$MODEL/tokenizer.json
echo "=== LIBS PRESENTES ==="
ls /vendor/lib64/ | grep -E "cdsprpc|fastrpc"
echo "=== LANCEMENT GENIEX CLIENT (root) ==="
cd /data/local/tmp
./geniex_client2 "$MODEL" "$TOK"
echo "=== EXIT CODE: $? ==="
