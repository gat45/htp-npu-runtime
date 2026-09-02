#!/system/bin/sh
# Check if NPU is active: count FastRPC signals + temps
# Usage: sh check_npu_active.sh
# >0 fastrpc signals during workload = NPU active; >70C = hot

echo "=== NPU ACTIVITY CHECK ==="
echo "Time: $(date +%H:%M:%S)"

# Count fastrpc signals (kernel tracepoint)
if [ -d /sys/kernel/debug/tracing ]; then
  F1=$(grep -c 'fastrpc' /sys/kernel/debug/tracing/trace_pipe 2>/dev/null || echo 0)
  sleep 1
  F2=$(grep -c 'fastrpc' /sys/kernel/debug/tracing/trace_pipe 2>/dev/null || echo 0)
  echo "fastrpc_signals: $((F2 - F1)) (delta over 1s)"
else
  echo "fastrpc_signals: no tracing available"
fi

# Count from dmesg if tracing unavailable
DM=$(dmesg 2>/dev/null | grep -ci 'fastrpc' || echo 0)
echo "fastrpc_dmesg_count: $DM"

# Temperatures (real, excluding trip)
echo "=== Temps (real zones) ==="
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null)
  case "$t" in
    *trip*) continue ;;
  esac
  case "$t" in
    gpuss*|gpu*|cpu*|cluster*|soc*|ddr*|tsens*)
      v=$(cat "$z/temp" 2>/dev/null)
      [ -n "$v" ] && echo "$t: $((v/1000))C"
      ;;
  esac
done | sort -t: -k2 -rn | head -5

echo "=== fastrpc-cdsp device ==="
ls -la /dev/fastrpc-cdsp 2>/dev/null
echo "=== Done ==="