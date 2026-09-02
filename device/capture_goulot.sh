#!/bin/bash
# Capture métriques goulot LLM - lecture seule
# Usage: sh capture_goulot.sh <duree_secondes> <intervalle>
DUR=${1:-30}
INT=${2:-1}
OUT=/data/local/tmp/goulot_$(date +%H%M%S).csv
echo "ts,gpu_busy_pct,gpu_clock_mhz,ram_bw_mbps,cpu_user,cpu_sys,cpu_idle,mem_avail_mb,htp_temp" > $OUT

END=$((SECONDS+DUR))
while [ $SECONDS -lt $END ]; do
  TS=$(date +%s)
  # GPU busy (lecture seule)
  GB=$(cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null | tr -d '\n')
  # Format: <busy> <total> -> pct
  BUSY=$(echo $GB | awk '{print $1}')
  TOTAL=$(echo $GB | awk '{print $2}')
  if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ] 2>/dev/null; then
    PCT=$((BUSY*100/TOTAL))
  else
    PCT=-1
  fi
  # GPU clock
  CLK=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null | tr -d '\n')
  # RAM bandwidth (si dispo)
  BW=$(cat /sys/kernel/debug/ddr_bw 2>/dev/null | tr -d '\n')
  # CPU stats
  CPU=$(head -1 /proc/stat | awk '{print $2, $3, $4, $5}')
  CU=$(echo $CPU | awk '{print $1}')
  CS=$(echo $CPU | awk '{print $2}')
  CI=$(echo $CPU | awk '{print $4}')
  # Memoire
  MEM=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
  # Temp HTP/NPU
  TMP=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1)
  echo "$TS,$PCT,$CLK,$BW,$CU,$CS,$CI,$MEM,$TMP" >> $OUT
  sleep $INT
done
echo "DONE $OUT"
cat $OUT