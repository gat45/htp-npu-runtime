#!/system/bin/sh
echo "=== REPONSE LLM ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*full_text|decode_time|generated_tokens|stop_reason" | tail -5
echo "=== UI CHAT (reponse affichee) ==="
uiautomator dump /data/local/tmp/sc6.xml 2>&1
grep -oE 'text="[^"]{1,120}"' /data/local/tmp/sc6.xml | grep -v systemui | tail -10
