#!/system/bin/sh
# e7_ngl0_all.sh — E7 : ngl=0 (aucune couche offloadée) avec -dev dans tous les sens.
# Auto (scheduler) / GPUOpenCL / HTP0 / ordres croisés. Capture T avant/apres.
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e7_ngl0_all.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

snapline(){ T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); echo "@$1 temp=$T" >> $LOG; }

# ---- Ordre 1 : AUTO -> GPU -> NPU ----
snapline "start_o1_auto"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -o json >> $LOG 2>&1
snapline "end_o1_auto"
snapline "start_o1_gpu"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -dev GPUOpenCL -o json >> $LOG 2>&1
snapline "end_o1_gpu"
snapline "start_o1_htp"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -dev HTP0 -o json >> $LOG 2>&1
snapline "end_o1_htp"

# ---- Ordre 2 : NPU -> GPU -> AUTO ----
snapline "start_o2_htp"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -dev HTP0 -o json >> $LOG 2>&1
snapline "end_o2_htp"
snapline "start_o2_gpu"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -dev GPUOpenCL -o json >> $LOG 2>&1
snapline "end_o2_gpu"
snapline "start_o2_auto"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -o json >> $LOG 2>&1
snapline "end_o2_auto"