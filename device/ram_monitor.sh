#!/system/bin/sh
export LD_LIBRARY_PATH=/data/local/tmp/npu
export ADSP_LIBRARY_PATH=/data/local/tmp/npu
export GGML_HEXAGON_NDEV=1
cd /data/local/tmp/npu

M=/data/local/tmp/Qwen3.5-9B-D2-A.gguf

read_mem() {
  cat /proc/meminfo | awk '/MemFree/ {print "MemFree:"$2"kB"} /Cached/ {print "Cached:"$2"kB"}'
}

echo "=== RAM monitor during HTP0 run ==="
echo "BEFORE: $(read_mem)"

./llama-bench -m $M -ngl 99 -p 16 -n 16 -t 8 -dev HTP0 > /data/local/tmp/ram_bench.log 2>&1 &
BPID=$!

for i in 1 2 3 4 5 6 7 8; do
  sleep 10
  echo "t+$((i*10))s $(read_mem)"
done

wait $BPID
echo "AFTER: $(read_mem)"
echo "=== Result ==="
grep -E '^\| qwen.*tg' /data/local/tmp/ram_bench.log 2>/dev/null | tail -1