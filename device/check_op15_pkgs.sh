#!/system/bin/sh
for p in com.op15.toolkit com.op15.toolkit.current com.op15.toolkit.legacy com.op15.toolkit.scout com.op15.toolkit.opencoderoot; do
  echo "== $p =="
  dumpsys package $p 2>/dev/null | grep -E 'versionName|lastUpdateTime|codePath' | head -4
done