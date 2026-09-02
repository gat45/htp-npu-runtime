#!/system/bin/sh
# Diagnostic root : politiques Magisk + uids des apps toolkit
echo "===POLICIES MAGISK==="
su -c 'magisk --sqlite "SELECT * FROM policies"' 2>&1
echo "===UIDS==="
for p in com.op15.toolkit com.op15.toolkit.current com.op15.toolkit.scout com.op15.toolkit.legacy com.op15.opencoderoot; do
  u=$(dumpsys package $p 2>/dev/null | grep -m1 "userId=" | tr -d ' ')
  echo "$p -> $u"
done
echo "===MAGISK LOG (queue)==="
ls /cache/magisk.log /data/adb/magisk.log 2>/dev/null
tail -30 /data/adb/magisk.log 2>/dev/null | grep -iE "su|request|policy|deny|allow" | tail -12
echo "===TEST SU DEPUIS SHELL==="
su -c 'echo SU_SHELL_OK; id -u'
