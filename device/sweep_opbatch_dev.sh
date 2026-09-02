#!/system/bin/sh
# sweep_opbatch_dev.sh — attaque le mur pipeline : GGML_HEXAGON_OPBATCH × OPQUEUE.
# Point fixe : attnQ4 ngl33 (sweet spot decode upstream 7.07 t/s).
BIN=/data/local/tmp/instr/llama-bench
LIB=/data/local/tmp/instr
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP-attnQ4.gguf
OUT=/data/local/tmp/sweep_opbatch.out
export LD_LIBRARY_PATH=$LIB ADSP_LIBRARY_PATH=$LIB GGML_HEXAGON_NDEV=1 GGML_HEXAGON_ARCH=v81 GGML_HEXAGON_PROFILE=3

: > $OUT
echo "START temp=$(cat /sys/class/thermal/thermal_zone0/temp) $(date +%s%3N)" >> $OUT
run() {
  NAME=$1; OB=$2; OQ=$3
  T0=$(cat /sys/class/thermal/thermal_zone0/temp)
  echo "=== [$NAME] OPBATCH=$OB OPQUEUE=$OQ t0=$T0 ===" >> $OUT
  T1=$(date +%s%3N)
  GGML_HEXAGON_OPBATCH=$OB GGML_HEXAGON_OPQUEUE=$OQ \
  timeout 240 $BIN -m $M -dev HTP0 -ngl 33 -p 8 -n 8 -r 1 -t 8 >> $OUT 2>&1
  echo "RC=$? wall_ms=$(( $(date +%s%3N) - T1 )) t_end=$(cat /sys/class/thermal/thermal_zone0/temp)" >> $OUT
  sleep 4
}

# OPBATCH sweep (OPQUEUE = défaut 16)
for OB in 16 32 64 128 256 512 1024 2048; do
  run "objatch_$OB" $OB 16
done
# OPQUEUE sweep (OPBATCH = défaut 1024)
for OQ in 2 4 8 32 64; do
  run "opqueue_$OQ" 1024 $OQ
done

echo "END temp=$(cat /sys/class/thermal/thermal_zone0/temp) $(date +%s%3N)" >> $OUT
echo DONE