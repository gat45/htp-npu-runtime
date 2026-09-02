#!/system/bin/sh
LOG=/data/local/tmp/llama-server.log
pkill -f llama-server 2>/dev/null
i=0
while [ $i -lt 15 ]; do
  if ! (ss -tln 2>/dev/null | grep -q ':8080' || netstat -tln 2>/dev/null | grep -q ':8080'); then
    break
  fi
  i=$((i + 1))
  sleep 1
done
nohup /data/local/tmp/llama-server \
  -m /data/local/tmp/qwen3.5-9b-pocketpal/qwen3.5-9b-q4_0.gguf \
  --host 127.0.0.1 --port 8080 \
  -c 8192 -np 1 -t 8 --no-webui \
  > $LOG 2>&1 &
echo "started pid $!"
