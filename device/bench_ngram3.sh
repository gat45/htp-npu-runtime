#!/system/bin/sh
R=/data/local/tmp/npu28202
export LD_LIBRARY_PATH=$R ADSP_LIBRARY_PATH=$R GGML_HEXAGON_NDEV=1 GGML_HEXAGON_ARCH=v81
cd $R
pkill -f npu28202/llama-server 2>/dev/null; sleep 2
# prompt long ~300 tokens: repetition riche pour le ngram
PROMPT="The history of computing is a long story of innovation and discovery. From the early mechanical calculators of the seventeenth century to the modern electronic computers of today, each generation of machines has built upon the work of its predecessors. The analytical engine of Charles Babbage, the theoretical work of Alan Turing, the first electronic computers like ENIAC, the invention of the transistor, the development of integrated circuits, the personal computer revolution, the rise of the internet, and now the era of artificial intelligence. Each of these milestones represents a significant step forward in our ability to process information. The history of computing is a long story of innovation and discovery. From the early mechanical calculators of the seventeenth century to the modern electronic computers of today, each generation of machines has built upon the work of its predecessors. The analytical engine of Charles Babbage, the theoretical work of Alan Turing, the first electronic computers like ENIAC, the invention of the transistor, the development of integrated circuits, the personal computer revolution, the rise of the internet, and now the era of artificial intelligence. Each of these milestones represents a significant step forward in our ability to process information."
nohup ./llama-server -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off --spec-default --host 127.0.0.1 --port 8535 > /data/local/tmp/npu28202/ngram3_server.log 2>&1 &
i=0
while [ $i -lt 90 ]; do
  if curl -s -m 3 http://127.0.0.1:8535/health 2>/dev/null | grep -q '"status":"ok"'; then break; fi
  if ! kill -0 $! 2>/dev/null; then echo "SERVER DIED"; tail -5 /data/local/tmp/npu28202/ngram3_server.log; exit 1; fi
  i=$((i+1)); sleep 3
done
echo "READY after ${i}x3s"
curl -s -X POST http://127.0.0.1:8535/completion -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"$PROMPT\",\"n_predict\":64,\"temperature\":0}" > /data/local/tmp/npu28202/ngram3_resp.json
sleep 2
grep -E "eval time|draft acceptance|mean len|graphs reused" /data/local/tmp/npu28202/ngram3_server.log | tail -3
pkill -f npu28202/llama-server; sleep 2
echo "KILLED"
