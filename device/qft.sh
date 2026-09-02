#!/system/bin/sh
# Optrace-like QAIRT : capture ftrace (fastrpc/sched) pendant un bench QNN
T=/sys/kernel/tracing
OUT=/data/local/tmp/qairt_ftrace.txt
echo 0 > $T/tracing_on 2>/dev/null
echo 32768 > $T/buffer_size_kb 2>/dev/null
for ev in fastrpc arm_smmu interconnect_qcom sched; do
  echo 1 > $T/events/$ev/enable 2>/dev/null
done
> $T/trace
echo 1 > $T/tracing_on
cd /data/local/tmp
export LD_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export ADSP_LIBRARY_PATH=/data/local/tmp:/data/local/tmp/gxlibs
export CDSP_LIBRARY_PATH=/data/local/tmp
./geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -n 32 \
  > /data/local/tmp/qairt_bench.log 2>&1
echo 0 > $T/tracing_on
grep -aE "fastrpc_|map_pages|iommu_|sched_switch" $T/trace > "$OUT"
wc -l "$OUT"
tail -4 /data/local/tmp/qairt_bench.log