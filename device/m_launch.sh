#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 3
uiautomator dump /data/local/tmp/m1.xml 2>&1
BTN=$(grep -oE '<node[^>]*text="Chat agents / LLM \(GenieX\)"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' /data/local/tmp/m1.xml | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1)
X=$(echo $BTN | grep -oE '[0-9]+' | sed -n '1p'); Y1=$(echo $BTN | grep -oE '[0-9]+' | sed -n '2p'); X2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '3p'); Y2=$(echo $BTN | grep -oE '[0-9]+' | sed -n '4p')
CX=$(( (X + X2) / 2 )); CY=$(( (Y1 + Y2) / 2 ))
input tap $CX $CY
sleep 3
uiautomator dump /data/local/tmp/m2.xml 2>&1
grep -oE 'text="[^"]{1,40}"' /data/local/tmp/m2.xml | grep -v systemui | head -15
