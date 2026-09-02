#!/system/bin/sh
# bench_abc_dev.sh — Expérience décisive A/B/C contrôlée (protocole red-team)
# A = attention Q8_0 (mixte) · B = attention Q4_0 · C = attention MXFP4
BIN=/data/local/tmp/instr/llama-bench
LIB=/data/local/tmp/instr
OUT=/data/local/tmp/bench_abc.out
export LD_LIBRARY_PATH=$LIB ADSP_LIBRARY_PATH=$LIB GGML_HEXAGON_NDEV=1 GGML_HEXAGON_ARCH=v81
: > $OUT
echo "START temp=$(cat /sys/class/thermal/thermal_zone0/temp) $(date +%s%3N)" >> $OUT
run() {
  NAME=$1; G=$2
  T0=$(cat /sys/class/thermal/thermal_zone0/temp)
  echo "=== [$NAME] t0=$T0 ===" >> $OUT
  timeout 200 $BIN -m $G -dev HTP0 -ngl 99 -p 8 -n 8 -r 1 -t 8 >> $OUT 2>&1
  echo "RC=$? t_end=$(cat /sys/class/thermal/thermal_zone0/temp)" >> $OUT
  sleep 5
}
run "A_mixte_q8"  /data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf
run "B_attnQ4"    /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
run "C_attnMXFP4" /data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnMXFP4.gguf
echo "END temp=$(cat /sys/class/thermal/thermal_zone0/temp)" >> $OUT
echo DONE