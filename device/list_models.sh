#!/system/bin/sh
# Inventaire des LLM sur l'appareil (taille + chemin)
for f in $(find /sdcard /data/local/tmp /data/data/com.termux/files/home -type f \( -iname "*.gguf" -o -iname "*.safetensors" -o -iname "*.bin" -o -iname "*.model" \) 2>/dev/null | grep -v -E "apt/(srcpkgcache|pkgcache|.*\.bin$)"); do
  sz=$(stat -c '%s' "$f" 2>/dev/null)
  if [ -n "$sz" ]; then
    hum=$(echo "$sz" | awk '{ if ($1 >= 1073741824) printf "%.2f Go", $1/1073741824; else if ($1 >= 1048576) printf "%.1f Mo", $1/1048576; else printf "%d Ko", $1/1024 }')
    echo "$hum | $f"
  fi
done
