#!/system/bin/sh
# Campagne runtimes — bench 9B Q4_0 tg16 (même config pour comparer les piles)
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
echo "=== JZ (fork gat45, mempool MBUF=3400) ==="
cd /data/local/tmp/jz
export LD_LIBRARY_PATH=/data/local/tmp/jz/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/jz/lib CDSP_LIBRARY_PATH=/data/local/tmp/jz/lib
export GGML_HEXAGON_NDEV=1 GGML_HEXAGON_MBUF=3400
./bin/llama-bench -m $MODEL -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 2>/dev/null | grep -E "pp128|tg16"

echo "=== NPU-PILE (GenieX libs 09317338 via bench/) ==="
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/bench/lib:/vendor/lib64:/system/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/bench/lib CDSP_LIBRARY_PATH=/data/local/tmp/bench/lib
export GGML_HEXAGON_NDEV=1
./llama-bench -m $MODEL -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 2>/dev/null | grep -E "pp128|tg16"

echo "=== BENCH-LIB-CPU (lib_cpu, HTP) ==="
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/bench/lib_cpu:/vendor/lib64:/system/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/bench/lib_cpu CDSP_LIBRARY_PATH=/data/local/tmp/bench/lib_cpu
./llama-bench -m $MODEL -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 2>/dev/null | grep -E "pp128|tg16"
echo "DONE"