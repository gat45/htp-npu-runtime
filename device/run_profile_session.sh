#!/system/bin/sh
# Session de profilage complete : serveur + attente + profil par-token
export LD_LIBRARY_PATH=/data/local/tmp/npu:/vendor/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export CDSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3200
PY=/data/data/com.termux/files/usr/bin/python3

# 1. tuer toute instance precedente
pkill -f llama-server 2>/dev/null
sleep 2

# 2. demarrer le serveur
cd /data/local/tmp/npu
./bin/llama-server \
    -m /data/local/tmp/Qwen3.8-9B-Cyber-Exploit-Agent-v3-Q4_0.gguf \
    -ngl 60 -t 6 --ctx-size 4096 \
    --host 127.0.0.1 --port 18181 &
SRV=$!

# 3. attendre que l'API reponde (max 8 min)
i=0
while [ $i -lt 96 ]; do
    if curl -s -m 3 http://127.0.0.1:18181/health | grep -q ok; then
        echo "[session] API prete apres ${i}x5s"
        break
    fi
    if ! kill -0 $SRV 2>/dev/null; then
        echo "[session] ERREUR: serveur mort pendant le chargement"
        exit 1
    fi
    sleep 5
    i=$((i+1))
done

if [ $i -ge 96 ]; then
    echo "[session] ERREUR: timeout chargement"
    exit 1
fi

# 4. profilage par-token + memoire + SMMU
$PY /data/local/tmp/npu_mem_profiler.py \
    --url http://127.0.0.1:18181/v1 \
    --prompt "Explique en detail comment fonctionne un NPU Snapdragon." \
    --max-tokens 256 \
    --out /data/local/tmp/prof_results/prof_$(date +%H%M%S)
RC=$?

# 5. arreter proprement le serveur
kill $SRV 2>/dev/null
echo "[session] termine rc=$RC"
exit $RC
