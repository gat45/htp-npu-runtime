#!/system/bin/sh
echo "=== DECOUVERTES LLM (GenieXSdk full_text) ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*full_text|GenieXSdk.*H[0-9]|GenieXSdk.*CONFIRMED|GenieXSdk.*CANDIDATE|GenieXSdk.*DISPROVEN|GenieXSdk.*SUSPECTED|GenieXSdk.*Risque|GenieXSdk.*FastRPC" | tail -30
echo "=== RAPPORTS SCOUT ==="
ls -t /sdcard/Documents/SecurityScout/*.md 2>/dev/null | head -5
