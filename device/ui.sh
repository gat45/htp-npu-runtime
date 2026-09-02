#!/system/bin/sh
echo "=== UI DUMP (boutons) ==="
uiautomator dump /data/local/tmp/ui.xml 2>&1
grep -oE 'text="[^"]*"|resource-id="[^"]*"' /data/local/tmp/ui.xml 2>/dev/null | head -40
