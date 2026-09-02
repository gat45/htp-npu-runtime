#!/system/bin/sh
echo "=== SCOUT LIBS ==="
ls /data/app/*/com.op15.toolkit.scout*/lib/arm64/ 2>/dev/null | grep -iE "geniex|QnnHtp|ggml-htp|cdsprpc" | head -20
echo "=== SCOUT MODEL ==="
find /data/user/0/com.op15.toolkit.scout -name "geniex.json" 2>/dev/null | head
ls /data/user/0/com.op15.toolkit.scout/files/geniex/models/qualcomm/ 2>/dev/null
echo "=== SCOUT RAG DB ==="
ls -la /data/user/0/com.op15.toolkit.scout/databases/ 2>/dev/null
