cp -r /data/local/tmp/shamiko_files/. /data/adb/modules/shamiko/
chmod -R 0755 /data/adb/modules/shamiko
find /data/adb/modules/shamiko -type f -exec chmod 0644 {} ;
rm -rf /data/local/tmp/shamiko_files
echo '--- contenu ---'
find /data/adb/modules/shamiko -type f
