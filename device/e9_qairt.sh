#!/system/bin/sh
# e9_qairt.sh — E9 : bench QAIRT (burst, config actuelle), froid, thermal sampling.
# But : debloquer le bench QAIRT (LD path + libgeniex_vlm.so) et mesurer le pic burst.
BUNDLE=/data/local/tmp/qwen3-8b-w4a16
LOG=/data/local/tmp/e9_qairt.log
SAMP=/data/local/tmp/e9_qairt_samples.log
OUT=/data/local/tmp/e9_qairt_bench.log
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/qairt:/data/local/tmp/gxlibs:/vendor/lib64:/system/lib64
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/qairt:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp

echo "START temp=$(cat /sys/class/thermal/thermal_zone0/temp)" > $SAMP
/data/local/tmp/geniex-bench --plugin qairt --device npu \
    -m "$BUNDLE" -n 64 > $OUT 2>&1 &
BPID=$!
i=0
while [ $i -lt 90 ]; do
  kill -0 $BPID 2>/dev/null || break
  echo "S t=${i}s temp=$(cat /sys/class/thermal/thermal_zone0/temp)" >> $SAMP
  i=$((i+2)); sleep 2
done
wait $BPID
echo "EXIT=$? temp=$(cat /sys/class/thermal/thermal_zone0/temp)" >> $SAMP
echo "END temp=$(cat /sys/class/thermal/thermal_zone0/temp)" >> $SAMP