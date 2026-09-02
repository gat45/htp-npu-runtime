#!/system/bin/sh
# e8_matrix.sh — E8 : matrice backends complete, ngl=99, 2 ordres croises.
# 1 CPU pur (-ngl 0)  2 GPU 3 NPU 4 AUTO(-dev) 5 GPU,NPU 6 NPU,GPU
# 7 GPU,NPU -ts 1,99  8 NPU,GPU -ts 99,1
MODEL=/data/local/tmp/qwen3.5-9b-q4_0/qwen3.5-9b-q4_0.gguf
LOG=/data/local/tmp/e8_matrix.log
cd /data/local/tmp/npu || exit 1
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400

snapline(){ T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); echo "@$1 temp=$T" >> $LOG; }

# ORDRE A : CPU, GPU, NPU, AUTO, GPU,NPU, NPU,GPU, GPU,NPU ts=1,99, NPU,GPU ts=99,1
snapline "A_cpu_pur"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -o json >> $LOG 2>&1
snapline "A_gpu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL -o json >> $LOG 2>&1
snapline "A_npu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0 -o json >> $LOG 2>&1
snapline "A_auto"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -o json >> $LOG 2>&1
snapline "A_gpunpu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL,HTP0 -o json >> $LOG 2>&1
snapline "A_npugpu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0,GPUOpenCL -o json >> $LOG 2>&1
snapline "A_gpunpu_ts"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL,HTP0 -ts 1,99 -o json >> $LOG 2>&1
snapline "A_npugpu_ts"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0,GPUOpenCL -ts 99,1 -o json >> $LOG 2>&1

# ORDRE B : inverse
snapline "B_npugpu_ts"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0,GPUOpenCL -ts 99,1 -o json >> $LOG 2>&1
snapline "B_gpunpu_ts"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL,HTP0 -ts 1,99 -o json >> $LOG 2>&1
snapline "B_npugpu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0,GPUOpenCL -o json >> $LOG 2>&1
snapline "B_gpunpu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL,HTP0 -o json >> $LOG 2>&1
snapline "B_auto"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -o json >> $LOG 2>&1
snapline "B_npu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev HTP0 -o json >> $LOG 2>&1
snapline "B_gpu"
./llama-bench -m $MODEL -ngl 99 -p 128 -n 32 -t 6 -dev GPUOpenCL -o json >> $LOG 2>&1
snapline "B_cpu_pur"
./llama-bench -m $MODEL -ngl 0 -p 128 -n 32 -t 6 -o json >> $LOG 2>&1