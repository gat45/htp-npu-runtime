#!/system/bin/sh
uiautomator dump /data/local/tmp/disc_ui.xml 2>&1
echo "=== REPONSE LLM DANS L'UI ==="
grep -oE 'text="[^"]{1,300}"' /data/local/tmp/disc_ui.xml | grep -v systemui | tail -20
