#!/system/bin/sh
OUT="/data/local/tmp/fcrash"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "=== BEFORE ==="
date
uname -a
getprop ro.board.platform
getprop ro.build.fingerprint
getenforce

echo "=== REMOTEPROC BEFORE ==="
for R in /sys/class/remoteproc/remoteproc*; do
  [ -d "$R" ] || continue
  echo "[$R]"
  for F in name state; do
    [ -r "$R/$F" ] && printf "%s=" "$F" && cat "$R/$F"
  done
done

echo "=== DMESG BEFORE ==="
dmesg 2>/dev/null | grep -Ei 'fastrpc|adsprpc|cdsprpc|cdsp|adsp|smmu|iommu|dma.buf|remoteproc|qcom' > "$OUT/dmesg_before.txt"
wc -l "$OUT/dmesg_before.txt"

echo "=== RUN GENIEX CLIENT ==="
export LD_LIBRARY_PATH=/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64:/vendor/dsp/cdsp
export ADSP_LIBRARY_PATH=/vendor/dsp/adsp
export CDSP_LIBRARY_PATH=/vendor/dsp/cdsp
export GENIEX_LOG_LEVEL=off
export GENIEX_PLUGIN_PATH=/data/local/tmp/plug
MODEL=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
TOK=$MODEL/tokenizer.json
cd /data/local/tmp
./geniex_client2 "$MODEL" "$TOK" 2>&1
echo "CLIENT_EXIT=$?"

echo "=== AFTER ==="
date
dmesg 2>/dev/null | grep -Ei 'fastrpc|adsprpc|cdsprpc|cdsp|adsp|smmu|iommu|dma.buf|remoteproc|qcom' > "$OUT/dmesg_after.txt"
wc -l "$OUT/dmesg_after.txt"

echo "=== REMOTEPROC AFTER ==="
for R in /sys/class/remoteproc/remoteproc*; do
  [ -d "$R" ] || continue
  echo "[$R]"
  for F in name state; do
    [ -r "$R/$F" ] && printf "%s=" "$F" && cat "$R/$F"
  done
done

echo "=== DIFF ==="
diff -u "$OUT/dmesg_before.txt" "$OUT/dmesg_after.txt" > "$OUT/dmesg.diff" 2>&1
cat "$OUT/dmesg.diff"

echo "=== FAULTS ==="
grep -Ei 'fault|translation|permission|context|smmu|iommu|invalid|abort|reset|timeout|crash|panic|bad|failed' "$OUT/dmesg_after.txt"

echo "=== RESULT DIR: $OUT ==="
