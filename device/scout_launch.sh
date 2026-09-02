#!/system/bin/sh
input keyevent KEYCODE_WAKEUP
sleep 1
wm dismiss-keyguard 2>/dev/null
am start -n com.op15.toolkit.scout/.SecurityScoutActivity
sleep 4
uiautomator dump /data/local/tmp/scout_ui.xml 2>&1
grep -oE 'text="[^"]{1,40}"|resource-id="com.op15.toolkit[^"]*"' /data/local/tmp/scout_ui.xml | grep -v systemui | head -15
