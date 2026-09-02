#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64:/vendor/dsp/cdsp
export ADSP_LIBRARY_PATH=/vendor/dsp/adsp
export CDSP_LIBRARY_PATH=/vendor/dsp/cdsp
export GENIEX_LOG_LEVEL=trace
export GENIEX_PLUGIN_PATH=/data/local/tmp/gxlibs
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
TOK=$MODEL/tokenizer.json
cd /data/local/tmp
./geniex_client2 "$MODEL" "$TOK" 2>&1
echo "EXIT=$?"
