#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 3
uiautomator dump /data/local/tmp/s1.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Lancer le scan"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/s1.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN=$BTN"
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
echo "SCAN $(date +%T)"
sleep 12
echo "=== LOGCAT (REFUSED/NOT_COLLECTED/FastRPC) ==="
logcat -d 2>/dev/null | grep -iE "ScoutReadOnly|NOT_COLLECTED|find_vma|vma_lookup|dma_buf|FastRPC|frpc" | tail -20
