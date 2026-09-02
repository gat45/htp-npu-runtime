#!/system/bin/sh
# run_8b_htp0_mem.sh — run unique 8B Q4_K_M sur HTP0 SEUL (ngl99), mesure le pic
# mémoire réellement adressé par UNE session HTP (plafond single-HTP > 3.4 Go ?).
# Usage: sh run_8b_htp0_mem.sh
M=/data/local/tmp/Qwen3-8B-Q4_K_M.gguf
BENCH=/data/local/tmp/npu/llama-bench
LIB=/data/local/tmp/npu
OUT=/data/local/tmp/run8b_htp0.log
MEM=/data/local/tmp/run8b_htp0.mem.csv
TIMEOUT=180

export LD_LIBRARY_PATH=$LIB
export ADSP_LIBRARY_PATH=$LIB
export GGML_HEXAGON_NDEV=1
export GGML_HEXAGON_MBUF=5000
export GGML_HEXAGON_USE_HMX=1

: > "$OUT"
echo "START $(date +%s%3N) MemAvail=$(awk '/MemAvailable/{print int(\$2/1024)}' /proc/meminfo) t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" > "$MEM"

$BENCH -m "$M" -dev HTP0 -ngl 99 -t 6 -p 32 -n 8 -r 1 > "$OUT" 2>&1 &
BPID=$!

# monitoring RSS/PSS du process + mémoire système pendant chargement+décode
i=0
MAXRSS=0
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
echo "END $(date +%s%3N) maxrss_kB=${MAXRSS}k MemAv_free_MB=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) end_t0=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)" >> "$MEM"
echo "=== RUN 8B HTP0 SEUL RESULT ==="
grep -aE "qwen|pp32|tg8|vmem|model buffer|HTP0|error|Abort|load" "$OUT" | head -15
echo "--- PIC MEMOIRE ---"
grep -aE "maxrss|END" "$MEM" | tail -2