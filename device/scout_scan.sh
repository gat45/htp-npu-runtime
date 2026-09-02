#!/system/bin/sh
# Trouver le bouton "Lancer le scan" et taper dessus
uiautomator dump /data/local/tmp/scout_ui3.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Lancer le scan"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/scout_ui3.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN=$BTN"
# centre du bouton
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p')
Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p')
X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p')
Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 ))
CY=$(( (Y1 + Y2) / 2 ))
echo "TAP $CX $CY"
input tap $CX $CY
echo "SCAN LANCE $(date +%T)"
sleep 15
echo "=== LOGCAT SCOUT ==="
logcat -d -t 200 2>/dev/null | grep -iE "scout|SecurityScout|find_vma|vma_lookup|FastRPC|finding|versions" | tail -20
