#!/system/bin/sh
B=/data/local/tmp/qwen3-8b-w4a16
echo "=== metadata.json (recherche spill/vtcm) ==="
cat $B/metadata.json 2>/dev/null | grep -iE "spill|fill|vtcm|tcm|layout|bin|shard|precision|dtype" | head -20
echo "=== htp_backend_ext_config.json ==="
cat $B/htp_backend_ext_config.json 2>/dev/null
echo "=== fichiers .bin shards ==="
ls -la $B/*.bin 2>/dev/null
echo "=== search spillFill dans TOUT le bundle (strings) ==="
grep -raoE "spill[A-Za-z]*[=: ]*[0-9]+" $B 2>/dev/null | head -8
