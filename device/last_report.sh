#!/system/bin/sh
echo "=== RAPPORTS SCOUT (derniers) ==="
ls -t /sdcard/Documents/SecurityScout/*.md 2>/dev/null | head -3
