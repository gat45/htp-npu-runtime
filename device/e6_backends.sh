#!/system/bin/sh
# e6_backends.sh — E6 : CPU / GPU / NPU SEPARES (jamais en meme temps), ordres differents,
# un seul HTP, ngl 99. Chaque run = 1 process, capture T avant/apres + buffers.
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e6_backends.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

snapline(){ T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); echo "@$1 temp=$T" >> $LOG; }

# ---- Ordre 1 : CPU -> GPU -> NPU(HTP0) ----
snapline "start_order1_CPU"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev CPU -o json >> $LOG 2>&1
snapline "end_order1_CPU"
snapline "start_order1_GPU"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL -o json >> $LOG 2>&1
snapline "end_order1_GPU"
snapline "start_order1_NPU"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0 -o json >> $LOG 2>&1
snapline "end_order1_NPU"

# ---- Ordre 2 : NPU -> GPU -> CPU (ordre inverse) ----
snapline "start_order2_NPU"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0 -o json >> $LOG 2>&1
snapline "end_order2_NPU"
snapline "start_order2_GPU"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL -o json >> $LOG 2>&1
snapline "end_order2_GPU"
snapline "start_order2_CPU"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev CPU -o json >> $LOG 2>&1
snapline "end_order2_CPU"