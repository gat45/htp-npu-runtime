#!/system/bin/sh
# Scan plus large : /sdcard complet + repertoires GenieX/AI Hub + PocketPal
echo "=== /sdcard (gguf/safetensors) ==="
find /sdcard -type f \( -iname "*.gguf" -o -iname "*.safetensors" \) 2>/dev/null | while read f; do
  sz=$(stat -c '%s' "$f" 2>/dev/null)
  [ -n "$sz" ] && echo "$(echo "$sz" | awk '{ if ($1>=1073741824) printf "%.2f Go",$1/1073741824; else if ($1>=1048576) printf "%.1f Mo",$1/1048576; else printf "%d Ko",$1/1024 }') | $f"
done

echo "=== Dossiers GenieX / AI Hub / QNN / PocketPal ==="
for d in \
  /data/local/tmp/models \
  /data/local/tmp/GenieX \
  /data/local/tmp/geniex \
  /data/local/tmp/aihub \
  /data/local/tmp/qnn \
  /data/local/tmp/npu \
  /sdcard/Download \
  /sdcard/PocketPal \
  /sdcard/Models \
  /data/data/com.termux/files/home \
  /sdcard/Android/data/com.artificialmind.aihub/files \
  /sdcard/Android/data/com.pocketpal/files; do
  if [ -d "$d" ]; then
    echo "--- $d ---"
    ls -la "$d" 2>/dev/null | head -20
  fi
done
