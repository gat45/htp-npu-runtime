#!/system/bin/sh
input keyevent KEYCODE_WAKEUP
sleep 1
input keyevent 82
sleep 1
wm dismiss-keyguard 2>/dev/null
input swipe 540 2000 540 800 300
sleep 2
am start -n com.op15.toolkit/.NpuChatActivity
sleep 3
echo "=== UI ==="
uiautomator dump /data/local/tmp/ui.xml 2>&1
grep -oE 'text="[^"]{1,30}"|class="[^"]*EditText[^"]*"|resource-id="[^"]*"' /data/local/tmp/ui.xml 2>/dev/null | grep -vE "systemui|keyguard|StatusBar|NavigationBar" | head -30
