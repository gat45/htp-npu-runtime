#!/system/bin/sh
SRC=/data/user/0/com.op15.toolkit/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
DST=/data/user/0/com.op15.toolkit.scout/files/geniex/models/qualcomm/Qwen3-4B-Instruct-2507
mkdir -p "$DST"
cp "$SRC"/* "$DST"/ 2>&1
chmod -R 755 /data/user/0/com.op15.toolkit.scout/files/geniex 2>/dev/null
echo "=== RESULTAT ==="
ls -la "$DST" 2>/dev/null | head -20
du -sh "$DST" 2>/dev/null
