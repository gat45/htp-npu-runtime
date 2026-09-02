#!/system/bin/sh
echo "=== env QNN profiling/log ==="
strings /data/local/tmp/libgeniex_core.so /data/local/tmp/gxlibs/libQnnHtp.so 2>/dev/null \
  | grep -iE "^QNN_|GENIEX_.*PROF|profiling|profile_file|log_level" | head -12
echo "=== decode_speculative dans plugin ==="
strings /data/local/tmp/libgeniex_plugin.so 2>/dev/null | grep -iE "speculative|draft|mtp|Profiler" | head -6