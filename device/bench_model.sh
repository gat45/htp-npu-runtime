#!/system/bin/sh
# Bench generique : sh bench_model.sh <model.gguf> <ngl> <tag>
export LD_LIBRARY_PATH=/data/local/tmp/npu:/vendor/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3200
PY=/data/data/com.termux/files/usr/bin/python3

MODEL=$1
NGL=${2:-80}
TAG=${3:-bench}

pkill -f llama-server 2>/dev/null
sleep 2

cd /data/local/tmp/npu
./bin/llama-server \
    -m "$MODEL" \
    -ngl $NGL -t 6 --ctx-size 2048 -ub 16 -fa on --no-mmap \
    --host 127.0.0.1 --port 18181 &
SRV=$!

i=0
while [ $i -lt 96 ]; do
    if curl -s -m 3 http://127.0.0.1:18181/health | grep -q ok; then
        echo "[$TAG] API prete apres ${i}x5s"
        break
    fi
    if ! kill -0 $SRV 2>/dev/null; then
        echo "[$TAG] ERREUR: serveur mort"
        exit 1
    fi
    sleep 5
    i=$((i+1))
done

$PY /data/local/tmp/npu_mem_profiler.py \
    --url http://127.0.0.1:18181/v1 \
    --prompt "Explique en detail comment fonctionne un NPU Snapdragon." \
    --max-tokens 192 \
    --out /data/local/tmp/prof_results/$TAG

kill $SRV 2>/dev/null
echo "[$TAG] termine"
