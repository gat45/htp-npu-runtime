for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat $z/type 2>/dev/null)
  case "$t" in
    cpu-*|qmx-*|npu*)
      v=$(cat $z/temp 2>/dev/null)
      case "$v" in ''|*[!0-9]*) continue;; esac
      if [ "$v" -ge 30000 ] 2>/dev/null && [ "$v" -le 80000 ] 2>/dev/null; then echo "$t=$v"; fi;;
  esac
done | sort -t= -k2 -n | tail -3
