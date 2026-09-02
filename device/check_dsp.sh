#!/system/bin/sh
echo "=== DSP SUBSYSTEMS ==="
for i in 0 1 2 3 4 5 6 7; do
  n=$(cat /sys/bus/msm_subsys/subsys${i}/name 2>/dev/null)
  s=$(cat /sys/bus/msm_subsys/subsys${i}/state 2>/dev/null)
  c=$(cat /sys/bus/msm_subsys/subsys${i}/crash_count 2>/dev/null)
  echo "subsys${i}: ${n} state=${s} crashes=${c}"
done

echo ""
echo "=== FASTRPC DEVICES ==="
ls -la /dev/fastrpc-* 2>/dev/null

echo ""
echo "=== DSP BOOT STATE ==="
cat /sys/kernel/boot_cdsp/ssr 2>/dev/null || echo "N/A"

echo ""
echo "=== KERNEL DMESG (fastrpc/cdsp last 15 lines) ==="
dmesg | grep -iE "fastrpc|cdsp|nsp|htp|hexagon" | tail -15

echo ""
echo "=== RUNNING DSP PROCESSES ==="
ps -A | grep -iE "cdsp|dsp|hexagon|nsp" 2>/dev/null

echo ""
echo "=== SKEL FILES CHECK ==="
ls /data/local/tmp/libggml-htp-v81*.so 2>/dev/null
echo "Skel files anywhere:"
find /data/local/tmp -maxdepth 3 -name "*Skel*v81*" 2>/dev/null
find /data/local/tmp -maxdepth 3 -name "*Skel*ggml*" 2>/dev/null
