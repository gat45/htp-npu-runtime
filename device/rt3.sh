#!/system/bin/sh
MODEL=/data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf
echo "=== NPU-PILE (GenieX libs bench/) ==="
cd /data/local/tmp/bench
export LD_LIBRARY_PATH=/data/local/tmp/bench/lib
export ADSP_LIBRARY_PATH=/data/local/tmp/bench/lib
export CDSP_LIBRARY_PATH=/data/local/tmp/bench/lib
export GGML_HEXAGON_NDEV=1
./llama-bench -m $MODEL -ngl 99 -p 128 -n 16 -r 1 -dev HTP0 > /data/local/tmp/npupile.log 2>&1
echo "EXIT=$?"
tail -8 /data/local/tmp/npupile.log
echo ""
echo "=== QAIRT (geniex-bench bundle 8B w4a16) ==="
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
./geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 32 > /data/local/tmp/qairt.log 2>&1
echo "EXIT=$?"
tail -14 /data/local/tmp/qairt.log