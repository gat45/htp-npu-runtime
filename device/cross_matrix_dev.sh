#!/system/bin/sh
# cross_matrix_dev.sh — Matrice CPU/GPU/NPU (sm=layer) dans tous les ordres exprimables.
# Constraintes estable : CPU est rejete par -dev (parseur arg.cpp:1130) → CPU = fallback
# de queue (couches >= ngl). L'ordre des backends par couche = [dev listes] puis CPU.
# Ordres testes (11) :
#   seul     : CPU(ngl0), GPU(ngl99), NPU(ngl99)
#   paires   : GPU>NPU, NPU>GPU, GPU>CPU, NPU>CPU
#   triplets : GPU>NPU>CPU, NPU>GPU>CPU  (+ GPU>CPU>NPU et NPU>CPU>GPU via ngl partiel)
# Usage: sh cross_matrix_dev.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
BIN=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/cross_matrix.out
export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

: > "$OUT"
T0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
echo "MATRIX_START temp0=$T0 $(date +%s%3N)" >> "$OUT"

hz() { cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null; }
hvx() { for z in /sys/class/thermal/thermal_zone*; do case "$(cat $z/type 2>/dev/null)" in nsphvx-*) echo "$(cat $z/temp 2>/dev/null)";; esac; done; }

run_one() {
  NAME="$1"; shift
  T0=$(hz); HVX0=$(hvx | tr '\n' ',')
  echo "=== RUN [$NAME] t0=$T0 hvx0=[$HVX0] ===" >> "$OUT"
  T1=$(date +%s%3N)
  timeout 240 "$BIN" -m "$M" "$@" -p 8 -n 8 -r 1 -t 8 >> "$OUT" 2>&1
  RC=$?
  T2=$(date +%s%3N); T3=$(hz); HVX1=$(hvx | tr '\n' ',')
  echo "RC=$RC wall_ms=$((T2-T1)) t_end=$T3 hvx1=[$HVX1]" >> "$OUT"
  sleep 3
}

# — seuls —
run_one "CPU p0"            -ngl 0
run_one "GPU p99"           -dev GPUOpenCL -ngl 99
run_one "NPU p99"           -dev HTP0 -ngl 99
# — paires (ordre de split layer) —
run_one "GPU>NPU p99"       -dev GPUOpenCL/HTP0 -ngl 99
run_one "NPU>GPU p99"       -dev HTP0/GPUOpenCL -ngl 99
run_one "GPU>CPU p66"       -dev GPUOpenCL -ngl 66
run_one "NPU>CPU p66"       -dev HTP0 -ngl 66
# — triplets —
run_one "GPU>NPU>CPU p66"   -dev GPUOpenCL/HTP0 -ngl 66
run_one "NPU>GPU>CPU p66"   -dev HTP0/GPUOpenCL -ngl 66
run_one "GPU>CPU p33_NPUq"  -dev GPUOpenCL -ngl 33
run_one "NPU>CPU p33_GPUq"  -dev HTP0 -ngl 33

echo "MATRIX_END temp_end=$(hz) $(date +%s%3N)" >> "$OUT"
echo "DONE"