#!/system/bin/sh
cd /data/local/tmp/gxlibs
echo "=== libQnnHtp.so spec/draft/mtp ==="
strings libQnnHtp.so 2>/dev/null | grep -iE "specul|draft|mtp|accept" | head -6
echo "=== libQnnHtpNetRunExtensions.so ==="
strings libQnnHtpNetRunExtensions.so 2>/dev/null | grep -iE "specul|draft|mtp|accept" | head -6
echo "=== plugin qairt (geniex) ==="
strings /data/local/tmp/libgeniex*.so 2>/dev/null | grep -iE "specul|draft|mtp|accept" | head -6
echo "=== profiling symbols (optrace) ==="
strings libQnnChrometraceProfilingReader.so 2>/dev/null | grep -iE "chrometrace|optrace|profile" | head -5