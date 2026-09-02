#!/system/bin/sh
am start -n com.op15.toolkit.scout/com.op15.toolkit.SecurityScoutActivity
sleep 4
uiautomator dump /data/local/tmp/sg.xml 2>&1
grep -oE 'text="[^"]{1,40}"|resource-id="com.op15.toolkit[^"]*"' /data/local/tmp/sg.xml | grep -v systemui | head -20
