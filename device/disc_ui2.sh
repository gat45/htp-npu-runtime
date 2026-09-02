#!/system/bin/sh
uiautomator dump /data/local/tmp/disc_ui2.xml 2>&1
echo "=== REPONSE LLM (textes) ==="
grep -oE 'text="[^"]{1,200}"' /data/local/tmp/disc_ui2.xml | grep -v systemui | tail -25
