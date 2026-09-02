#!/system/bin/sh
set -eu

VARIANT="${1:-forced}"
PORT="${2:-18082}"
MODEL="/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf"
BASE="$(dumpsys package com.geniex.demo | sed -n 's/.*legacyNativeLibraryDir=//p' | head -n 1)"
NATIVE="$BASE/arm64"
SERVER="$NATIVE/libcustom_runtime_server.so"
LOG="/data/local/tmp/variant_${VARIANT}.log"
RESP="/data/local/tmp/variant_${VARIANT}.json"

export LD_LIBRARY_PATH="$NATIVE"
export ADSP_LIBRARY_PATH="$NATIVE"
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81
export GGML_HEXAGON_MAX_MUL_MAT_ROWS=32768

EXTRA=""
case "$VARIANT" in
  forced) EXTRA="-dev HTP0" ;;
  auto) EXTRA="" ;;
  forced_output_cpu) EXTRA="-dev HTP0 -ot output.weight=CPU" ;;
  auto_output_cpu) EXTRA="-ot output.weight=CPU" ;;
  *) echo "unknown variant: $VARIANT"; exit 2 ;;
esac

rm -f "$LOG" "$RESP"
# shellcheck disable=SC2086
"$SERVER" -m "$MODEL" --host 127.0.0.1 --port "$PORT" --jinja -ngl 99 \
  -c 4096 -t 6 -tb 6 -b 1024 -ub 256 -fa auto --fit on --parallel 1 \
  --cache-prompt --no-webui --spec-type draft-mtp $EXTRA >"$LOG" 2>&1 &
PID=$!

READY=0
for I in $(seq 1 120); do
  if ! kill -0 "$PID" 2>/dev/null; then break; fi
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done

if [ "$READY" != 1 ]; then
  echo "VARIANT=$VARIANT START_FAILED"
  tail -80 "$LOG"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  exit 3
fi

curl -fsS --max-time 600 "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"local","stream":false,"temperature":0,"max_tokens":128,"messages":[{"role":"user","content":"Explique en une phrase pourquoi le ciel est bleu."}],"chat_template_kwargs":{"enable_thinking":false}}' >"$RESP"

echo "VARIANT=$VARIANT"
grep -o '"prompt_per_second":[0-9.]*\|"predicted_per_second":[0-9.]*\|"draft_n":[0-9]*\|"draft_n_accepted":[0-9]*' "$RESP" || true
grep -E 'graph splits|repack tensor output.weight|assigned to device|draft acceptance|device_info|buffer size' "$LOG" | tail -35 || true
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
