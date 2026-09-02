#!/system/bin/sh
# sweep_d2_ubatch.sh — Test #4 (Hang HMX #24963) : varier ubatch sur D2-A-MTP ngl99
# pour voir si un petit ubatch contourne le hang op_pending=16 err=46.
# Usage: sh sweep_d2_ubatch.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/sweep_ub.log
TIMEOUT=150

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=3400
export GGML_HEXAGON_USE_HMX=1

: > "$OUT"

run() {  # $1=tag, reste=args
  local tag=$1; shift
  echo "=== $tag $(date +%s%3N) ===" >> "$OUT"
  timeout "$TIMEOUT" "$BENCH" "$@" 2>&1 | grep -aE "qwen|pp|tg|error|Abort|SPIN" >> "$OUT"
  local rc=$?
  echo ">>> $tag rc=$rc timeout=$TIMEOUT" >> "$OUT"
}

# ngl99 avec différentes tailles d'ubatch (le batch prompt reste 32)
run "n99_ub32"   -m "$M" -dev HTP0 -ngl 99 -t 6 -p 32 -n 8 -r 1 -b 32  -ub 16
run "n99_ub64"   -m "$M" -dev HTP0 -ngl 99 -t 6 -p 32 -n 8 -r 1 -b 64  -ub 32
run "n99_ub128"  -m "$M" -dev HTP0 -ngl 99 -t 6 -p 32 -n 8 -r 1 -b 128 -ub 64
# plus gros prompt (512) pour forcer plusieurs under-batches de decode
run "n99_ub256_p512" -m "$M" -dev HTP0 -ngl 99 -t 6 -p 512 -n 8 -r 1 -b 512 -ub 128
run "n99_ub32_p512"  -m "$M" -dev HTP0 -ngl 99 -t 6 -p 512 -n 8 -r 1 -b 512 -ub 32

echo "=== UBATCH SWEEP RESULT ==="
grep -aE "=== |>>> |qwen" "$OUT"