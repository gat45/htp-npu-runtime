#!/system/bin/sh
echo "=== SDK VERSION FILES ==="
find /data/app -path "*com.op15.toolkit*" -name "*.so" 2>/dev/null | head -1
ls /data/app/~~enUFc62gOqdVhV0URaPt4Q==/com.op15.toolkit-auY0hTcRwJgMFN4KatpT0g==/ 2>/dev/null
echo "=== APK VERSION ==="
dumpsys package com.op15.toolkit 2>/dev/null | grep -E "versionName|versionCode" | head -2
echo "=== MODEL TOOL-VERSIONS ==="
cat /data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507/tool-versions.yaml 2>/dev/null
echo "=== AIHUB ==="
ls /data/user/0/com.op15.toolkit/files/geniex/aihub/ 2>/dev/null
cat /data/user/0/com.op15.toolkit/files/geniex/aihub/*.json 2>/dev/null | head -20
