#!/system/bin/sh
# sweep_ngl_matrice.sh — Sweep ngl sur HTP0 (runtime instr upstream).
# Trouver le sweet spot decode CPU<->HTP du GGUF attnQ4 (5.07 GiB, 9B D2-A-MTP).
# Usage: sh sweep_ngl_matrice.sh
BIN=/data/local/tmp/instr/llama-bench
LIB=/data/local/tmp/instr
M4=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf   # attn q4_0 (candidat quotidien)
MO=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf          # mixte (reference)
OUT=/data/local/tmp/sweep_ngl.out
export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_ARCH=v81

: > "$OUT"
echo "SWEEP_START temp=$(cat /sys/class/thermal/thermal_zone0/temp) $(date +%s%3N)" >> "$OUT"

run_ngl() {
  NAME="$1"; GGUF="$2"; NGL="$3"; N="$4"
  T0=$(cat /sys/class/thermal/thermal_zone0/temp)
  echo "=== [$NAME] ngl=$NGL n=$N t0=$T0 ===" >> "$OUT"
  T1=$(date +%s%3N)
  timeout 240 "$BIN" -m "$GGUF" -dev HTP0 -ngl "$NGL" -p 8 -n "$N" -r 1 -t 8 >> "$OUT" 2>&1
  RC=$?
  T2=$(date +%s%3N); T3=$(cat /sys/class/thermal/thermal_zone0/temp)
  echo "RC=$RC wall_ms=$((T2-T1)) t_end=$T3" >> "$OUT"
  sleep 3
}

# — attnQ4 : sweep fin (decode tg8 ET tg16, prefill pp8) —
for NGL in 33 40 50 60 66 75 90; do
  run_ngl "attnQ4" "$M4" "$NGL" 8
done
# tg16 pour confirmer le sweet spot en generation plus longue
for NGL in 33 66 75 90; do
  run_ngl "attnQ4-n16" "$M4" "$NGL" 16
done
# — mixte : controle 3 points (baseline du +34% d'origine) —
for NGL in 50 66 90; do
  run_ngl "MIXTE" "$MO" "$NGL" 8
done

echo "SWEEP_END temp=$(cat /sys/class/thermal/thermal_zone0/temp) $(date +%s%3N)" >> "$OUT"
echo DONE