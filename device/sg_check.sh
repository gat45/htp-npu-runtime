#!/system/bin/sh
echo "=== PROCESS SCOUT ==="
pidof com.op15.toolkit.scout
echo "=== LOGCAT GenieXSdk ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk|geniex|qairt|Qwen3|ScoutGeniex|snapnpu" | tail -25
echo "=== UI ACTUELLE ==="
uiautomator dump /data/local/tmp/sg3.xml 2>&1
grep -oE 'text="[^"]{1,80}"' /data/local/tmp/sg3.xml | grep -v systemui | head -15
