#!/system/bin/sh
# prof_mtp_roundtrips.sh: profile llama-server base vs MTP avec GGML_HEXAGON_PROFILE=2
# usage: sh prof_mtp_roundtrips.sh <base|mtp>
# Sortie: /data/local/tmp/prof_<mode>.log (profile) + prof_<mode>_resp.json (timings)
export LD_LIBRARY_PATH=/data/local/tmp/instr
export GGML_HEXAGON_OPPOLL=1
export GGML_HEXAGON_OPPOLL_US=500
export GGML_HEXAGON_PROFILE=2
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
MODE=$1
PORT=8085
cd /data/local/tmp/instr
for p in $(pidof llama-server); do kill "$p" 2>/dev/null; done
sleep 3
EXTRA=""
if [ "$MODE" = "mtp" ]; then
  EXTRA="-md $MODEL --spec-type draft-mtp"
fi
rm -f /data/local/tmp/prof_$MODE.log /data/local/tmp/prof_$MODE_resp.json
timeout 250 ./llama-server $EXTRA -m "$MODEL" -dev HTP0 -ngl 33 -t 8 \
    --port $PORT --host 127.0.0.1 -c 1024 -n 128 --verbosity 5 \
    > /data/local/tmp/prof_$MODE.log 2>&1 &
SRV=$!
H=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  sleep 2
  curl -s http://127.0.0.1:$PORT/health | grep -q "ok" && H=1 && break
done
echo "HEALTH=$H"
if [ "$H" = "1" ]; then
  curl -s -X POST http://127.0.0.1:$PORT/completion -H 'Content-Type: application/json' \
    -d '{"prompt":"Write a short story about a robot learning to cook pasta for the first time.","n_predict":64,"stream":false,"temperature":0.8,"seed":42}' \
    > /data/local/tmp/prof_$MODE_resp.json
  echo "RESP_SIZE=$(wc -c < /data/local/tmp/prof_$MODE_resp.json)"
fi
kill $SRV 2>/dev/null
for p in $(pidof llama-server); do kill "$p" 2>/dev/null; done
sleep 1
echo DONE