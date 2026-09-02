#!/system/bin/sh
BASE=http://127.0.0.1:4096

RESP=$(curl -s -X POST "$BASE/session" -H "Content-Type: application/json" -d '{}')
SID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
echo "SID=$SID"

# Envoi en arrière-plan (le POST bloque jusqu'à la fin du tour agent)
curl -s --max-time 90 -X POST "$BASE/session/$SID/message" -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"Reponds uniquement: 7 au carre egal"}]}' >/dev/null 2>&1 &

echo "=== attente 25s ==="
sleep 25

echo "=== resultat ==="
curl -s "$BASE/session/$SID/message" | grep -oE '"role":"assistant"[^}]*|"text":"[^"]*"' | tail -8
echo ""
echo "=== EXIT ==="
