#!/system/bin/sh
# test_placement_attnQ4.sh — HTP pures vs HTP->GPU vs GPU->HTP (runtime JZ, attnQ4)
# placement par ordre de split layer : -dev A/B = couches basses sur A puis B puis CPU
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
BIN=/data/local/tmp/npu/llama-bench
OUT=/data/local/tmp/placement_attnQ4.out
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

hz() { cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null; }

: > "$OUT"
echo "PLACEMENT_START temp=$(hz) $(date +%s%3N)" >> "$OUT"

run_one() {
  NAME="$1"; shift
  T0=$(hz)
  echo "=== RUN [$NAME] t0=$T0 ===" >> "$OUT"
  T1=$(date +%s%3N)
  timeout 240 "$BIN" -m "$M" "$@" -p 16 -n 16 -r 1 -t 8 >> "$OUT" 2>&1
  RC=$?
  T2=$(date +%s%3N); T3=$(hz)
  echo "RC=$RC wall_ms=$((T2-T1)) t_end=$T3" >> "$OUT"
  sleep 8
}

run_one "HTP_pure"     -dev HTP0 -ngl 33
run_one "HTP_GPU"      -dev HTP0/GPUOpenCL -ngl 33
run_one "GPU_HTP"      -dev GPUOpenCL/HTP0 -ngl 33
run_one "GPU_pure"     -dev GPUOpenCL -ngl 33

echo "PLACEMENT_END temp=$(hz) $(date +%s%3N)" >> "$OUT"
echo "DONE"