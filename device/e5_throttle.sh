#!/system/bin/sh
# e5_throttle.sh — E5 : long run decode soutenu pour observer le plateau thermal/throttle.
# ngl=48 (routage sature). p512 + n256 pour un decode long. Sampling T/cpu6/freq HTP pendant.
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e5_throttle.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

./llama-bench -m $MODEL -ngl 48 -p 512 -n 256 -t 6 -o json > $LOG 2>&1 &
BPID=$!
# samplage toutes les 2s pendant au plus ~240s
i=0
while [ $i -lt 120 ]; do
  kill -0 $BPID 2>/dev/null || break
  T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  C6=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null)
  echo "SAMPLE t=${i} temp=$T cpu6=$C6" >> /data/local/tmp/e5_samples.log
  i=$((i+2)); sleep 2
done
wait $BPID
echo "DONE temp=$(cat /sys/class/thermal/thermal_zone0/temp)" >> /data/local/tmp/e5_samples.log