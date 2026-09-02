#!/system/bin/sh
sleep 10
echo "=== RAPPORTS SCOUT ==="
ls -la /sdcard/Documents/SecurityScout/ 2>/dev/null | tail -5
echo "=== DERNIER MD ==="
LATEST=$(ls -t /sdcard/Documents/SecurityScout/*.md 2>/dev/null | head -1)
echo "FILE=$LATEST"
if [ -n "$LATEST" ]; then
  echo "--- VERSIONS ---"
  grep -A20 "## Versions de la pile" "$LATEST" | head -22
  echo "--- FINDINGS ---"
  grep -A30 "## Findings" "$LATEST" | head -32
fi
