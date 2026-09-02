#!/system/bin/sh
echo "=== DDR/DRAM clk ==="
for d in /sys/kernel/debug/clk/*ddr* /sys/kernel/debug/clk/*dram* /sys/kernel/debug/clk/*mem*; do
  [ -e "$d/clk_rate" ] && echo "$d: $(cat $d/clk_rate)"
done 2>/dev/null
echo "=== fastrpc ==="
ls /sys/kernel/debug/fastrpc/ 2>/dev/null
echo "=== l2 bench tps ==="
grep -E "tg16|pp128" /data/local/tmp/l2_bench.log 2>/dev/null | tail -4
echo "=== load avg / top cpu ==="
cat /proc/loadavg
echo "=== hexagon vmem ==="
ls /d/ 2>/dev/null | head; cat /sys/kernel/debug/fastrpc/*/vmem* 2>/dev/null | head -3
