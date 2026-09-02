#!/system/bin/sh
echo "=== MODELE OP15 TOOLKIT ==="
du -sh /data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507/ 2>/dev/null
ls /data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507/*.bin 2>/dev/null | wc -l
echo "=== ESPACE DISQUE ==="
df -h /data 2>/dev/null | tail -1
echo "=== SCOUT A-T-IL GENIEX SDK JAVA ? ==="
ls /data/app/*/com.op15.toolkit.scout*/base.apk 2>/dev/null | head -1
