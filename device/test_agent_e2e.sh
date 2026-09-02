#!/system/bin/sh
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
BASE=http://127.0.0.1:4096

RESP=$(curl -s -X POST "$BASE/session" -H "Content-Type: application/json" -d '{}')
SID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
echo "SID=$SID"

echo "=== send (text field) ==="
curl -s -X POST "$BASE/session/$SID/message" -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"Reponds uniquement: OK local"}]}' | head -c 700
echo ""
echo "=== wait 60s ==="
sleep 60
echo "=== list messages ==="
curl -s "$BASE/session/$SID/message" | head -c 2000
echo ""
echo "=== EXIT ==="
