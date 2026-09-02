MODPATH=/data/adb/modules/shamiko
rm -rf $MODPATH
mkdir -p $MODPATH
unzip -o /data/local/tmp/shamiko.zip -d $MODPATH >/dev/null 2>&1
chmod -R 0755 $MODPATH
echo '--- contenu ---'
find $MODPATH -type f