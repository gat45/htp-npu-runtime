#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
echo "=== /health ==="
curl -s http://127.0.0.1:8080/health 2>&1 | head -3
echo ""
echo "=== /v1/chat/completions ==="
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Reponds en un seul mot: pret"}],"max_tokens":30,"stream":false}' \
  2>&1 | head -40
echo ""
echo "=== EXIT ==="
