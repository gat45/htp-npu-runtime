#!/system/bin/sh
uiautomator dump /data/local/tmp/scout_ui4.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Enregistrer les rapports"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/scout_ui4.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN=$BTN"
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p')
Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p')
X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p')
Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 ))
CY=$(( (Y1 + Y2) / 2 ))
echo "TAP $CX $CY"
input tap $CX $CY
sleep 5
echo "=== RAPPORTS ==="
ls -t /sdcard/Documents/SecurityScout/*.md 2>/dev/null | head -2
