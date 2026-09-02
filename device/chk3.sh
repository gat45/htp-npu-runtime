#!/system/bin/sh
echo "=== ACTIVITY ==="
dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity|mResumedActivity" | head -2
echo "=== UI ACTUELLE ==="
uiautomator dump /data/local/tmp/uin.xml 2>&1
grep -oE 'text="[^"]{1,40}"|resource-id="com.op15.toolkit[^"]*"' /data/local/tmp/uin.xml | grep -v "systemui" | head -20
echo "=== LOGCAT npu/geniex/snapnpu ==="
logcat -d -t 500 2>/dev/null | grep -iE "snapnpu|geniex|qairt|npu_chat|NpuChat|model.*load|load.*model" | tail -30
