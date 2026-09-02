#!/system/bin/sh
logcat -d | grep -E "FATAL|Process: com.op15" -A 18 | tail -40
echo ===AMSTART===
am start -n com.op15.toolkit/.GovernorActivity 2>&1
sleep 4
logcat -d -t 200 | grep -E "FATAL EXCEPTION|AndroidRuntime" -A 14 | tail -30
