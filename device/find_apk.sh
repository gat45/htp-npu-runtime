#!/system/bin/sh
echo "=== APK dans /data/local/tmp ==="
find /data/local/tmp -maxdepth 3 -name "*.apk" 2>/dev/null
echo "=== APK dans /sdcard (Download, racine) ==="
find /sdcard -maxdepth 3 -name "*.apk" 2>/dev/null | head -40
echo "=== APK packages installés (perso = non système) ==="
pm list packages -f 2>/dev/null | grep -vE "/system/|/product/|/vendor/" | head -60