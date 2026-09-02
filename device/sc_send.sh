#!/system/bin/sh
# Trouver le champ de saisie et le bouton Envoyer
uiautomator dump /data/local/tmp/sc4.xml 2>&1
# Champ EditText
ET=$(grep -oE '<node[^>]*class="android.widget.EditText"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/sc4.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "ET=$ET"
X=$(echo $ET | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $ET | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $ET | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $ET | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
sleep 1
input text "Quels sont les risques FastRPC sur ce device?"
sleep 1
# Bouton Envoyer
uiautomator dump /data/local/tmp/sc5.xml 2>&1
SEND=$(grep -oE '<node[^>]*text="Envoyer"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/sc5.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
X=$(echo $SEND | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $SEND | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $SEND | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $SEND | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
echo "ENVOYE $(date +%T)"
sleep 30
echo "=== LOGCAT GenieXSdk generate ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk|generate|full_text|decode|ScoutChat" | tail -15
