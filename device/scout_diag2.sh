echo '=== BUFFER CRASH (scout) ==='
logcat -b crash -d | grep -aiE 'scout' | tail -15
echo '=== DROPBOX (crashes historiques) ==='
ls /data/system/dropbox/ 2>/dev/null | grep -iE 'scout|10409' | tail -10
ls /data/system/dropbox/ 2>/dev/null | tail -10
echo '=== FICHIERS LOG DU SCOUT ==='
find /data/data/com.op15.toolkit.scout -name '*.log' -o -name '*.txt' 2>/dev/null | head -10
ls -la /data/data/com.op15.toolkit.scout/files/ 2>/dev/null | head -12
echo '=== VERSION SCOUT ==='
dumpsys package com.op15.toolkit.scout | grep -E 'versionName|lastUpdateTime|firstInstallTime'