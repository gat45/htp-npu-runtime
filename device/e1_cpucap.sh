#!/system/bin/sh
# e1_cpucap.sh — E1 : brider CPU (cpufreq scaling_max_freq), 3 regimes,
# meme ngl (16,48,64) pour trancher T_thermal vs T_routing/splits vs T_CPU.
# Un seul job nohup = pas de cascade de crashes CDSP (doc RAPPORT_SESSION_20260827).
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e1_cpucap.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

P0=/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
P6=/sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
S0=$(cat $P0); S6=$(cat $P6)
echo "backup policy0=$S0 policy6=$S6" > $LOG

run_cap() {
  cap=$1; mx0=$2; mx6=$3
  su -c "echo $mx0 > $P0; echo $mx6 > $P6" 2>>$LOG
  T0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  C0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
  C6=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null)
  echo "=== cap=$cap mx0=$mx0 mx6=$mx6 temp0=$T0 cur0=$C0 cur6=$C6 ===" >> $LOG
  ./llama-bench -m $MODEL -ngl 16,48,64 -p 128 -n 16 -t 6 >> $LOG 2>&1
  T1=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  echo "=== cap=$cap END temp1=$T1 ===" >> $LOG
}

run_cap NORMAL $S0 $S6
run_cap CAP70 $((S0*70/100)) $((S6*70/100))
run_cap CAP50 $((S0*50/100)) $((S6*50/100))

# restore
su -c "echo $S0 > $P0; echo $S6 > $P6" 2>>$LOG
echo "=== RESTORED policy0=$S0 policy6=$S6 ===" >> $LOG