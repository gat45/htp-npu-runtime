#!/system/bin/sh
# e4_dense.sh — E4 : sweep dense ngl pour decoupler W_htp et N_splits.
# ngl bas (0,2,4,8,14) vs haut (16,32,48,64). Capture T + CPU freq avant/apres,
# + load_tensors buffers (probe verbose une fois a ngl=48 pour economiser).
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e4_dense.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

snapline(){ T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); C6=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null); echo "@$1 temp=$T cpu6=$C6" >> $LOG; }

for ngl in 0 2 4 8 14 16 32 48 64; do
  snapline "pre_N${ngl}"
  ./llama-bench -m $MODEL -ngl $ngl -p 128 -n 16 -t 6 -o json >> $LOG 2>&1
  snapline "post_N${ngl}"
done