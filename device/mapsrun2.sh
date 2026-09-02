#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64:/vendor/dsp/cdsp
export ADSP_LIBRARY_PATH=/vendor/dsp/adsp
export CDSP_LIBRARY_PATH=/vendor/dsp/cdsp
export GENIEX_LOG_LEVEL=off
export GENIEX_PLUGIN_PATH=/data/local/tmp/plug
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
cd /data/local/tmp
chmod 755 geniex_client2
./geniex_client2 "$MODEL" "$MODEL/tokenizer.json" 2>/tmp/gx.log &
CLIENT=$!
echo "CLIENT_PID=$CLIENT"
sleep 2
echo "=== MAPS geniex/Qnn/cdsp ==="
grep -E "libgeniex|libQnn|libcdsprpc|libadsprpc" /proc/$CLIENT/maps 2>/dev/null | grep -oE "/[^ ]+\.so" | sort -u
echo "=== copies libgeniex.so ==="
grep -c "libgeniex.so" /proc/$CLIENT/maps 2>/dev/null
echo "=== copies libgeniex_core ==="
grep -c "libgeniex_core.so" /proc/$CLIENT/maps 2>/dev/null
echo "=== LOG CLIENT ==="
cat /tmp/gx.log
wait $CLIENT
echo "EXIT=$?"
