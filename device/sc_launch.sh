#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 4
uiautomator dump /data/local/tmp/sc.xml 2>&1
grep -oE 'text="[^"]{1,50}"' /data/local/tmp/sc.xml | grep -v systemui | head -15
