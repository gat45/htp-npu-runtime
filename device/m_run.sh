#!/system/bin/sh
uiautomator dump /data/local/tmp/m3.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Mission"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/m3.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN=$BTN"
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
echo "MISSION LANCEE $(date +%T)"
sleep 45
echo "=== LOGCAT GenieXSdk mission ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*full_text|decode_time|generated_tokens|stop_reason|MISSION" | tail -8
