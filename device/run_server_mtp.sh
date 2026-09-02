#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

# Start llama-server with MTP in background
./llama-server --spec-type draft-mtp -m /data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf \
  -ngl 99 -t 8 -c 512 --port 8080 --host 127.0.0.1 \
  --no-webui --log-file /data/local/tmp/server_mtp.log 2>&1 &
SERVER_PID=$!
echo "server_pid=$SERVER_PID" > /data/local/tmp/server_mtp_run.log

# Wait for server to be ready (load model 7.8GB)
for i in $(seq 1 60); do
  sleep 3
  R=$(curl -s http://127.0.0.1:8080/health 2>/dev/null)
  echo "t+$((i*3))s health=$R" >> /data/local/tmp/server_mtp_run.log
  case "$R" in
    *ok*|*ready*)
      echo "SERVER READY at t+$((i*3))s" >> /data/local/tmp/server_mtp_run.log
      # Send a completion request to trigger MTP
      curl -s http://127.0.0.1:8080/completion -d '{"prompt":"The capital of France is","n_predict":16,"temperature":0}' \
        > /data/local/tmp/server_mtp_resp.json 2>&1
      echo "RESPONSE_DONE" >> /data/local/tmp/server_mtp_run.log
      break
      ;;
  esac
done

# Keep server alive briefly then kill
sleep 5
kill $SERVER_PID 2>/dev/null
echo "SERVER_STOPPED" >> /data/local/tmp/server_mtp_run.log