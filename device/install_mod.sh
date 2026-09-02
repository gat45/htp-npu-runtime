MODPATH=/data/adb/modules/op15_remote_priv
rm -rf $MODPATH
mkdir -p $MODPATH
unzip -o /data/local/tmp/op15_remote_priv.zip -d $MODPATH >/dev/null 2>&1
chmod -R 0755 $MODPATH
find $MODPATH -type f -exec chmod 0644 {} ;
echo '--- contenu ---'
find $MODPATH -type f