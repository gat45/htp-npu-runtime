#!/system/bin/sh
RUNTIME=/data/local/tmp/pr28202
MODEL=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
export LD_LIBRARY_PATH=$RUNTIME
export ADSP_LIBRARY_PATH=$RUNTIME
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
OUT=/data/local/tmp/sweep_pr28202
mkdir -p $OUT
run_cfg() {
  LABEL=$1; SPEC=$2; PORT=$3
  echo "{\"config\":\"$LABEL\",\"runs\":[" > $OUT/$LABEL.json
  FIRST=1
  for R in 1 2; do
    LOG=$OUT/${LABEL}_r${R}.log
    $RUNTIME/llama-server -m $MODEL -dev HTP0 -ngl 99 -t 8 -c 2048 --fit off --host 127.0.0.1 --port $PORT $SPEC > $LOG 2>&1 &
    SRV=$!
    I=0; while [ $I -lt 60 ]; do sleep 3; grep -q "listening on http" $LOG && break; I=$((I+1)); done
    curl -s -X POST http://127.0.0.1:$PORT/completion -H "Content-Type: application/json" -d "{\"prompt\":\"The capital of France is\",\"n_predict\":16,\"temperature\":0}" > $OUT/${LABEL}_r${R}_resp.json 2>/dev/null
    TPS=$(grep -o "\"predicted_per_second\":[0-9.]*" $OUT/${LABEL}_r${R}_resp.json | head -1 | cut -d: -f2)
    ACC=$(grep -oE "draft acceptance = [0-9.]+" $LOG | tail -1 | awk "{print \$NF}")
    [ -z "$TPS" ] && TPS=0; [ -z "$ACC" ] && ACC=null
    kill $SRV 2>/dev/null; sleep 2
    ps -A | grep llama | awk "{print \$2}" | xargs -r kill -9 2>/dev/null; sleep 2
    [ $FIRST = 1 ] || echo "," >> $OUT/$LABEL.json
    FIRST=0
    echo "{\"run\":$R,\"tg_tps\":$TPS,\"acceptance\":$ACC}" >> $OUT/$LABEL.json
    echo "[$LABEL r$R] tg=$TPS acc=$ACC"
    sleep 6
  done
  echo "]}" >> $OUT/$LABEL.json
}
run_cfg baseline "" 8090
run_cfg nmax1 "--spec-type draft-mtp --spec-draft-n-max 1" 8091
echo DONE
