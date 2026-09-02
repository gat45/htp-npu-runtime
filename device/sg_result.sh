#!/system/bin/sh
echo "=== RAPPORTS SCOUT (derniers) ==="
ls -t /sdcard/Documents/SecurityScout/*.md 2>/dev/null | head -3
echo "=== LOGCAT GenieXSdk generate ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk|generate|decode|token|synthese|synth?se|ScoutGeniex" | tail -20
