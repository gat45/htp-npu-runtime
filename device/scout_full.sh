#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 4
uiautomator dump /data/local/tmp/su.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Lancer le scan"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/su.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
echo "SCAN $(date +%T)"
sleep 12
uiautomator dump /data/local/tmp/su2.xml 2>&1
BTN2=$(grep -oE '<node[^>]*text="Enregistrer les rapports"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/su2.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
X=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
sleep 4
ls -t /sdcard/Documents/SecurityScout/*.md 2>/dev/null | head -1
