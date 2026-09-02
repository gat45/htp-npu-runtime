#!/system/bin/sh
uiautomator dump /data/local/tmp/sg2.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Analyse LLM \(GenieX\)"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/sg2.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN=$BTN"
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
echo "TAP $CX $CY"
input tap $CX $CY
echo "ANALYSE LLM LANCEE $(date +%T)"
sleep 30
echo "=== LOGCAT SCOUT GENIEX ==="
logcat -d -t 300 2>/dev/null | grep -iE "scout|geniex|qairt|Qwen3|model|npu|ScoutGeniex|erreur|error" | tail -30
