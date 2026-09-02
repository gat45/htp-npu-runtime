#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64
export GENIEX_PLUGIN_PATH=/data/local/tmp/plug
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
cd /data/local/tmp
chmod 755 geniex_client2
./geniex_client2 "$MODEL" "$MODEL/tokenizer.json" 2>/dev/null &
CLIENT=$!
sleep 3
echo "=== INODES libgeniex.so (copies distinctes?) ==="
grep "libgeniex.so" /proc/$CLIENT/maps 2>/dev/null | awk "{print \$6}" | sort -u
echo "=== LIGNES libgeniex.so ==="
grep "libgeniex.so" /proc/$CLIENT/maps 2>/dev/null
echo "=== INODES core ==="
grep "libgeniex_core.so" /proc/$CLIENT/maps 2>/dev/null | awk "{print \$6}" | sort -u
wait $CLIENT 2>/dev/null
echo DONE
