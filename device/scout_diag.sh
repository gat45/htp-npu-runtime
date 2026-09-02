echo '=== PID ==='
pidof com.op15.toolkit.scout
echo '=== MEMINFO scout ==='
dumpsys meminfo com.op15.toolkit.scout 2>/dev/null | head -30
echo '=== ALERTES ATHENA/EmJail scout ==='
logcat -d | grep -aE 'scout' | grep -aE 'EmJail|EmMem|Athena|abnormal|kill|ANR|FATAL|crash|ion' | tail -20
echo '=== CRASH/ANR scout ==='
logcat -d | grep -aiE 'scout.*(FATAL|crash|ANR|Exception)' | tail -10