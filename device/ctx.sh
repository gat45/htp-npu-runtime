#!/system/bin/sh
echo "=== ERREUR CONTEXTE ==="
logcat -d 2>/dev/null | grep -iE "context|exceed|too long|max_tokens|prompt.*token|ScoutGeniex|ScoutMission|Erreur" | tail -15
