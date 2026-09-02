#!/system/bin/sh
# Mesure dmabuf (taille totale des buffers dma-buf) par PID.
# Usage : su -c 'sh /data/local/tmp/dmabuf_meas.sh <pid1> <pid2> ...'
for pid in "$@"; do
  tot=0
  n=0
  for f in /proc/$pid/fdinfo/*; do
    s=$(grep -E '^size:' "$f" 2>/dev/null | awk '{print $2}')
    if [ -n "$s" ]; then
      tot=$((tot + s))
      n=$((n + 1))
    fi
  done
  echo "PID $pid : buffers=$n total=$((tot / 1048576)) Mo"
done
