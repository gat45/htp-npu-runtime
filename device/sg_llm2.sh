#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 4
uiautomator dump /data/local/tmp/sg4.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Analyse LLM \(GenieX\)"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/sg4.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
echo "ANALYSE $(date +%T)"
sleep 25
echo "=== LOGCAT GenieXSdk/ScoutGeniex ==="
logcat -d 2>/dev/null | grep -iE "ScoutGeniex|GenieXSdk|getPaths|npu_jni|qairt|Qwen3|UnsatisfiedLink|No implementation" | tail -20
