#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 3
uiautomator dump /data/local/tmp/fx1.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Chat agents / LLM \(GenieX\)"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/fx1.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
sleep 3
uiautomator dump /data/local/tmp/fx2.xml 2>&1
BTN2=$(grep -oE '<node[^>]*text="Agent autonome"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/fx2.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN2=$BTN2"
X=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN2 | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
echo "AGENT AUTONOME LANCE $(date +%T)"
sleep 60
echo "=== RESULTAT ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*(H[0-9]|L[0-9]|RED TEAM|R?FUT?|REFUTED|SUPPORT?|SUPPORTED|CONFIRMED|CANDIDATE|DISPROVEN|Statut|RAPPORT)" | tail -20
