#!/system/bin/sh
# e3_routing.sh — E3 : capture routage + taille buffers modèle par backend à ngl 16/32/48/64.
# But : associer TG à W_HTP réel (HTP0-REPACK) et n_splits -> régression T = T0 + a.W + g.N.
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e3_routing.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

for ngl in 16 32 48 64; do
  echo "##### NGL=$ngl START temp=$(cat /sys/class/thermal/thermal_zone0/temp) #####" >> $LOG
  ./llama-bench -m $MODEL -ngl $ngl -p 128 -n 16 -t 6 -v -o json >> $LOG 2>&1
  echo "##### NGL=$ngl END temp=$(cat /sys/class/thermal/thermal_zone0/temp) #####" >> $LOG
done