#!/system/bin/sh
# telemetry_sampler.sh — télémétrie temps réel POSIX (mksh Android-safe)
# Usage: sh telemetry_sampler.sh <fichier> [intervalle_s] [duree_max_s]
OUT="$1"; IV=${2:-1}; DUR=${3:-600}
: > "$OUT"
CPU_TMP=/data/local/tmp/.tl_cpu
get_cpu() { awk '/^cpu / {idle=$5+$6; tot=0; for(i=2;i<=8;i++) tot+=$i; printf "%d %d", idle, tot}' /proc/stat > "$CPU_TMP"; }
get_cpu
P1=$(awk '{print $1}' "$CPU_TMP"); P2=$(awk '{print $2}' "$CPU_TMP")
B1=$(awk '{print $1}' /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null); B1=${B1:-0}
T1=$(awk '{print $2}' /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null); T1=${T1:-0}
END=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$END" ]; do
  sleep "$IV"
  get_cpu
  N1=$(awk '{print $1}' "$CPU_TMP"); N2=$(awk '{print $2}' "$CPU_TMP")
  IDLE=$((N1-P1)); TOT=$((N2-P2))
  CPUPCT=-1; if [ "$TOT" -gt 0 ]; then CPUPCT=$(( 100*(TOT-IDLE)/TOT )); fi
  P1=$N1; P2=$N2
  B2=$(awk '{print $1}' /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null); B2=${B2:-0}
  T2=$(awk '{print $2}' /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null); T2=${T2:-0}
  GBUSY=-1; DT=$((T2-T1)); if [ "$DT" -gt 0 ]; then GBUSY=$(( 100*(B2-B1)/DT )); fi
  B1=$B2; T1=$T2
  GCLK=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null); GCLK=${GCLK:-0}
  TCPU=0; TGPU=0; TNPU=0; TDDR=0
  for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null); v=$(cat "$z/temp" 2>/dev/null)
    case "$t" in
      cpu-0-2-1|cpu-0-3-1|cpullc-1-1) if [ "$v" -gt "$TCPU" ]; then TCPU=$v; fi ;;
      gpuss-8|gpuss-9|gpuss-10)        if [ "$v" -gt "$TGPU" ]; then TGPU=$v; fi ;;
      nsphvx-*)                         if [ "$v" -gt "$TNPU" ]; then TNPU=$v; fi ;;
      ddr)                              if [ "$v" -gt "$TDDR" ]; then TDDR=$v; fi ;;
    esac
  done
  FC0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null); FC0=${FC0:-0}
  FC6=$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq 2>/dev/null); FC6=${FC6:-0}
  LA=$(awk '{print $1"/"$2"/"$3}' /proc/loadavg)
  MEMF=$(awk '/MemFree/ {print $2}' /proc/meminfo)
  echo "$(date +%s.%3N)|cpu%=$CPUPCT|gpu%=$GBUSY|t_cpu=$TCPU|t_gpu=$TGPU|t_npu=$TNPU|t_ddr=$TDDR|gpu_clk=$GCLK|freq0=$FC0|freq6=$FC6|load=$LA|memfree_kb=$MEMF" >> "$OUT"
done
echo "END" >> "$OUT"