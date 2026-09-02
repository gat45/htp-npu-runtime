#!/system/bin/sh
# Bench CPU pur : meme modele/options que le test HTP, sans NPU
pkill -f llama-server 2>/dev/null
sleep 2

export LD_LIBRARY_PATH=/data/local/tmp/npu:/vendor/lib64
cd /data/local/tmp/npu
./bin/llama-server \
    -m /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf \
    -ngl 0 \
    -c 2048 -ub 16 -fa on --no-mmap \
    -t 6 \
    --host 127.0.0.1 --port 18181 &
SRV=$!

i=0
while [ $i -lt 120 ]; do
    if curl -s -m 3 http://127.0.0.1:18181/health | grep -q ok; then
        echo "[cpu] API prete apres ${i}x5s"
        break
    fi
    if ! kill -0 $SRV 2>/dev/null; then
        echo "[cpu] ERREUR: serveur mort"
        exit 1
    fi
    sleep 5
    i=$((i+1))
done

PY=/data/data/com.termux/files/usr/bin/python3
$PY /data/local/tmp/npu_mem_profiler.py \
    --url http://127.0.0.1:18181/v1 \
    --prompt "Explique en detail comment fonctionne un NPU Snapdragon." \
    --max-tokens 256 \
    --out /data/local/tmp/prof_results/cpu_ngl0

kill $SRV 2>/dev/null
echo "[cpu] termine"
