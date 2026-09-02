#!/system/bin/sh
# run_9b_d2_htp0_mem.sh — TEST DÉCISIF : 9B D2-A-MTP complet sur UN SEUL HTP0.
# ngl99 / MBUF 5000 / pp32 / n8 court / watchdog strict + GGML_HEXAGON_PROFILE&VERBOSE
# pour capturer dimensions & cycles MUL_MAT. Discrimination capacité-vs-BW.
# Usage: sh run_9b_d2_htp0_mem.sh
M=/data/local/tmp/Qwen3.5-9B-D2-A-MTP.gguf   # 7.84 Go disque = 7.29 GiB GGUF (Q4_0, hybride Mamba-2)
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/run9b_d2_htp0.log
MEM=/data/local/tmp/run9b_d2_htp0.mem.csv
PROF=/data/local/tmp/run9b_d2_htp0.prof.txt
TIMEOUT=180

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=5000
export GGML_HEXAGON_USE_HMX=1
export GGML_HEXAGON_VERBOSE=1      # ops matmul + dimensions + buffers
export GGML_HEXAGON_PROFILE=2      # profiling par op (temps/cycles si dispo)

: > "$OUT"
echo "START $(date +%s%3N) MemAvail=$(awk '/MemAvailable/{print int(\$2/1024)}' /proc/meminfo) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" > "$MEM"

# watchdog global : si le process met > 180s, kill propre (évite hang CDSP)
(
  W=0
  while [ $W -lt $TIMEOUT ]; do
    sleep 5; W=$((W+5))
    pgrep -f "llama-bench -m /data/local/tmp/Qwen3.5-9B" >/dev/null || exit 0
  done
  echo "WATCHDOG: kill après ${TIMEOUT}s" >> "$MEM"
  pkill -9 -f "llama-bench -m /data/local/tmp/Qwen3.5-9B" 2>/dev/null
) & WDPID=$!

$BENCH -m "$M" -dev HTP0 -ngl 99 -t 6 -p 32 -n 8 -r 1 > "$OUT" 2>&1 &
BPID=$!

i=0; MAXRSS=0
while [ $i -lt 200 ]; do
  kill -0 $BPID 2>/dev/null || break
  i=$((i+1))
  RSS=$(awk '/VmRSS/{print $2}' /proc/$BPID/status 2>/dev/null); [ -z "$RSS" ] && RSS=0
  [ "${RSS%k}" -gt $MAXRSS ] 2>/dev/null && MAXRSS=${RSS%k}
  PSS=$(awk '/Pss:/{s+=$2} END{print s}' /proc/$BPID/smaps_rollup 2>/dev/null); [ -z "$PSS" ] && PSS=0
  MA=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
  G=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null); [ -z "$G" ] && G=0
  NSPH=""
  for z in /sys/class/thermal/thermal_zone*; do
    case "$(cat $z/type 2>/dev/null)" in nsphvx-*) NSPH="$NSPH $(cat $z/temp 2>/dev/null)";; esac
  done
  CPUS=""
  for c in 0 1 2 3 4 5 6 7; do
    f=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null); [ -z "$f" ] && f=0
    CPUS="${CPUS}$f,"
  done
  echo "$(date +%s%3N),rss_kB=${RSS}k,pss_kB=${PSS}k,maxrss_kB=${MAXRSS}k,MemAv_free_MB=$MA,gpu=$G,cpu=[${CPUS%,}],hvx=[$NSPH ]" >> "$MEM"
  sleep 1
done
wait $BPID
kill $WDPID 2>/dev/null
echo "END $(date +%s%3N) maxrss_kB=${MAXRSS}k MemAv_free_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MEM"
echo "PROFILE_DONE"

# séparer le profil verbose dans son propre fichier pour analyse MUL_MAT
grep -aE "matmul|MUL_MAT|HTP0 x|q[0-9]_[0-9].*->|profile|PROF|time|cycles|ms/op" "$OUT" > "$PROF" 2>/dev/null

echo "=== 9B D2 HTP0 SEUL RESULT ==="
grep -aE "qwen|pp32|tg8|vmem|model buffer|split_graph|splits|error|Abort|failed" "$OUT" | head -18
echo "--- PIC MEMOIRE ---"
grep -aE "maxrss_kB|END|WATCHDOG" "$MEM" | tail -2
echo "--- COUNT splits / backends ---"
grep -acE "split [0-9]*/.*backend=HTP0" "$OUT"
grep -acE "backend=CPU" "$OUT"