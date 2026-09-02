#!/system/bin/sh
B=/data/local/tmp/qwen3-8b-w4a16
echo "=== bundle ==="
ls -la $B 2>/dev/null | head -10
echo "=== spillFillBufferSize dans bundle ==="
for f in $B/*; do
  [ -f "$f" ] || continue
  n=$(strings "$f" 2>/dev/null | grep -c spillFill)
  [ "$n" -gt 0 ] && echo "$f: $n occurrence(s)"
done
echo "=== grep spillFill direct ==="
grep -rao "spillFillBufferSize[^,}]*" $B 2>/dev/null | head -5
echo "=== genie_config ==="
cat $B/genie_config.json 2>/dev/null | head -30
