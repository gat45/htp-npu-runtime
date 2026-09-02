#!/system/bin/sh
# llama-server benchmark: $1 = port, $2 = mtp|base, $3 = spec-draft-n-max (mtp only)
# MTP: -md <same gguf> --spec-type draft-mtp (tetes MTP natives du D2-A-MTP)
export LD_LIBRARY_PATH=/data/local/tmp/instr
export GGML_HEXAGON_OPPOLL=1
export GGML_HEXAGON_OPPOLL_US=500
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
cd /data/local/tmp/instr
PORT=$1
MODE=$2
NMAX=$3
for p in $(pidof llama-server); do kill "$p" 2>/dev/null; done
sleep 1
EXTRA=""
if [ "$MODE" = "mtp" ]; then
  EXTRA="-md $MODEL --spec-type draft-mtp"
  if [ -n "$NMAX" ]; then
    EXTRA="$EXTRA --spec-draft-n-max $NMAX"
  fi
fi
echo "=== llama-server port=$PORT mode=$MODE ==="
timeout 300 ./llama-server $EXTRA -m "$MODEL" -dev HTP0 -ngl 33 -t 8 \
    --port $PORT --host 127.0.0.1 -c 1024 -n 128 --verbosity 2 \
    > /data/local/tmp/server_$MODE.log 2>&1
echo "SERVER_RC=$?"
