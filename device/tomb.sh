#!/system/bin/sh
echo "=== TOMBSTONES ==="
ls -lt /data/tombstones/ 2>/dev/null | head -5
echo "=== CORE PATTERN ==="
cat /proc/sys/kernel/core_pattern 2>/dev/null
echo "=== DERNIER TOMBSTONE ==="
T=$(ls -t /data/tombstones/tombstone_* 2>/dev/null | head -1)
echo "FILE=$T"
if [ -n "$T" ]; then
  grep -A2 "backtrace" "$T" | head -10
  echo "--- REGISTERS ---"
  grep -A20 "registers" "$T" | head -25
fi
