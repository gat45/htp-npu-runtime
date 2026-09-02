#!/system/bin/sh
best=0
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null)
  case "$t" in
    gpuss*)
      v=$(cat "$z/temp" 2>/dev/null)
      if [ -n "$v" ] && [ "$v" -gt "$best" ]; then best=$v; fi
      ;;
  esac
done
echo "GPU_TEMP=$((best/1000))C"