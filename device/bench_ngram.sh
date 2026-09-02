#!/system/bin/sh
R=/data/local/tmp/npu28202
export LD_LIBRARY_PATH=$R ADSP_LIBRARY_PATH=$R GGML_HEXAGON_NDEV=1 GGML_HEXAGON_ARCH=v81
cd $R
pkill -f npu28202/llama-server 2>/dev/null; sleep 2
nohup ./llama-server -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off --spec-type ngram-mod --spec-ngram-mod-n-min 24 --spec-ngram-mod-n-max 64 --spec-ngram-mod-n-match 16 --host 127.0.0.1 --port 8533 > /data/local/tmp/npu28202/ngram_server.log 2>&1 &
i=0
while [ $i -lt 90 ]; do
  if curl -s -m 3 http://127.0.0.1:8533/health 2>/dev/null | grep -q '"status":"ok"'; then break; fi
  if ! kill -0 $! 2>/dev/null; then echo "SERVER DIED"; tail -5 /data/local/tmp/npu28202/ngram_server.log; exit 1; fi
  i=$((i+1)); sleep 3
done
echo "READY after ${i}x3s"
curl -s -X POST http://127.0.0.1:8533/completion -H 'Content-Type: application/json' \
  -d '{"prompt":"Write a short paragraph about Paris","n_predict":64,"temperature":0}' > /data/local/tmp/npu28202/ngram64_resp.json
sleep 2
grep -E "eval time|draft acceptance|mean len|graphs reused" /data/local/tmp/npu28202/ngram_server.log | tail -3
pkill -f npu28202/llama-server; sleep 2
echo "KILLED"
