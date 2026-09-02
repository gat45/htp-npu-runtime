#!/system/bin/sh
echo "=== LOGCAT SCOUT ==="
logcat -d 2>/dev/null | grep -iE "scout|SecurityScout|op15.toolkit.scout" | tail -40
echo "=== FICHIERS SCOUT ==="
find /sdcard/Documents/SecurityScout -type f 2>/dev/null | head -20
find /storage/emulated/0/Documents/SecurityScout -type f 2>/dev/null | head -20
echo "=== APP SCOUT ==="
pidof com.op15.toolkit.scout
