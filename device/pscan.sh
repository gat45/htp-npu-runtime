#!/system/bin/sh
echo "=== env vars de profilage dans libgeniex/plugin ==="
for f in /data/local/tmp/libgeniex*.so /data/local/tmp/gxlibs/libgeniex*.so /data/local/tmp/lib/*geniex*.so; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  strings "$f" 2>/dev/null | grep -iE "PROFILE|OPTRA|CHROME|TRACE|QNN_.*LEVEL|profile_level|profile_enabled" | head -8
done
echo "=== flags caches de geniex-bench ==="
strings /data/local/tmp/geniex-bench 2>/dev/null | grep -iE "profile|trace|optrace|verbose|log_level" | head -8