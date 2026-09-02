#!/system/bin/sh
# e2_abba.sh — E2 : ABBA thermique dans un seul llama-bench (16,64,64,16).
# But : isoler l'effet ngl de la derive thermique intra-process.
# Chaque bloc (A=ngl16, B=ngl64, B=64, A=16) est lance dans le MEME process avec
# capture T + freqs CPU avant/apres, pour voir si le dernier 16 retombe (~5)
# quand le premier faisait ~7.6, et si les 64 divergent entre eux.
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e2_abba.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

snapline() {
  label=$1
  T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  C0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
  C6=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null)
  echo "@$label temp=${T} cpu0=${C0} cpu6=${C6}" >> $LOG
}

snapline START_COLD
# Bloc A1 = ngl 16 (froid)
snapline PRE_A1
./llama-bench -m $MODEL -ngl 16 -p 128 -n 16 -t 6 >> $LOG 2>&1
snapline POST_A1
# Bloc B1 = ngl 64 (chaud)
snapline PRE_B1
./llama-bench -m $MODEL -ngl 64 -p 128 -n 16 -t 6 >> $LOG 2>&1
snapline POST_B1
# Bloc B2 = ngl 64 (plus chaud)
snapline PRE_B2
./llama-bench -m $MODEL -ngl 64 -p 128 -n 16 -t 6 >> $LOG 2>&1
snapline POST_B2
# Bloc A2 = ngl 16 (chaud, repete le 1er)
snapline PRE_A2
./llama-bench -m $MODEL -ngl 16 -p 128 -n 16 -t 6 >> $LOG 2>&1
snapline POST_A2_END