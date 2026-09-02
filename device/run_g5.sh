#!/system/bin/sh
mkdir -p /data/local/tmp/plug
cp /data/local/tmp/gxlibs/libgeniex_plugin_qairt.so /data/local/tmp/plug/
cp /data/local/tmp/gxlibs/libgeniex_plugin_llama_cpp.so /data/local/tmp/plug/
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64:/vendor/dsp/cdsp
export ADSP_LIBRARY_PATH=/vendor/dsp/adsp
export CDSP_LIBRARY_PATH=/vendor/dsp/cdsp
export GENIEX_LOG_LEVEL=off
export GENIEX_PLUGIN_PATH=/data/local/tmp/plug
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
TOK=$MODEL/tokenizer.json
cd /data/local/tmp
./geniex_client2 "$MODEL" "$TOK" 2>&1
echo "EXIT=$?"

