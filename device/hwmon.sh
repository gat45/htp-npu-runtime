#!/system/bin/sh
# hwmon.sh — échantillon temps réel CPU/GPU/NPU/RAM/batt/thermique (une passe)
# Sortie : lignes clé=valeur, parsées par l'app. Boucle à 1Hz côté app.
p=/sys/devices/system/cpu
# CPU % via /proc/stat (2 lectures)
s1=$(grep '^cpu ' /proc/stat)
sleep 0.5
s2=$(grep '^cpu ' /proc/stat)
read _ _ _ _ _ _ _ _ _ _ _ <<< "$s2"
# parse manuel
set -- $s2
tot2=$(( $2+$3+$4+$5+$6+$7+$8+$9+${10} ))
idle2=$(( $5+$6 ))
set -- $s1
tot1=$(( $2+$3+$4+$5+$6+$7+$8+$9+${10} ))
idle1=$(( $5+$6 ))
dt=$((tot2-tot1)); di=$((idle2-idle1))
if [ "$dt" -gt 0 ]; then cpu=$(( (100*(dt-di))/dt )); else cpu=0; fi
echo "cpu_pct=$cpu"
# freqs CPU (primaires)
echo "cpu0_freq=$(cat $p/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
echo "cpu4_freq=$(cat $p/cpu4/cpufreq/scaling_cur_freq 2>/dev/null)"
echo "cpu8_freq=$(cat $p/cpu8/cpufreq/scaling_cur_freq 2>/dev/null)"
# GPU : clk + busy%
gclk=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null)
gbusy=$(cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null)
echo "gpu_freq=$gclk"
set -- $gbusy
if [ -n "$2" ] && [ "$2" -gt 0 ]; then gpct=$(( $1*100/$2 )); else gpct=0; fi
echo "gpu_pct=$gpct"
# thermique NPU/GPU (zones)
for z in /sys/class/thermal/thermal_zone*; do
  t=$(cat "$z/type" 2>/dev/null); v=$(cat "$z/temp" 2>/dev/null)
  case "$t" in
    nsphvx-0) echo "npu_temp=$((v/1000))";;
    qmx-1-4) echo "npu_temp2=$((v/1000))";;
    gpuss-0) echo "gpu_temp=$((v/1000))";;
    cpullc-0-0) echo "cpu_temp=$((v/1000))";;
  esac
done
# RAM
mav=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
mtot=$(grep MemTotal /proc/meminfo | awk '{print $2}')
echo "ram_pct=$(( (mtot-mav)*100/mtot ))"
echo "ram_avail_mb=$((mav/1024))"
# batterie
echo "batt_pct=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
cur=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
vol=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)
if [ -n "$cur" ] && [ -n "$vol" ]; then
  w=$(( cur*vol/1000000000000 )); [ "$w" -lt 0 ] && w=$((-w))
  echo "batt_w=$w"
fi