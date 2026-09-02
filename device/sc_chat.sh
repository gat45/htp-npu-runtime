#!/system/bin/sh
uiautomator dump /data/local/tmp/sc2.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Chat agents / LLM \(GenieX\)"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/sc2.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
echo "BTN=$BTN"
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
sleep 4
uiautomator dump /data/local/tmp/sc3.xml 2>&1
grep -oE 'text="[^"]{1,50}"|resource-id="com.op15.toolkit[^"]*"' /data/local/tmp/sc3.xml | grep -v systemui | head -20
