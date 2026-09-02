#!/system/bin/sh
echo "=== CONTENU TRACE (10 lignes) ==="
head -10 /data/local/tmp/app_load_trace.txt
echo "=== ACTIVITY TOP ==="
dumpsys activity activities 2>/dev/null | grep -E "mResumedActivity|topResumedActivity" | head -3
echo "=== APP RUNNING? ==="
pidof com.op15.toolkit
echo "=== LOGCAT app (load/model/error) ==="
logcat -d -t 100 2>/dev/null | grep -iE "geniex|npu|qairt|model|SnapNPU|op15" | tail -25
