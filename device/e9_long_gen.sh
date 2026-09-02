#!/system/bin/sh
# e9_long_gen.sh - generation QAIRT longue + sampling thermal continu, SANS python.
# Le profil perf_profile DOIT etre deja pose dans htp_backend_ext_config.json.
# Usage (root) : sh /data/local/tmp/e9_long_gen.sh <label> <n_gen> <duration_s>
LABEL="${1:-sust}"
NGEN="${2:-1024}"
DUR="${3:-90}"
cd /data/local/tmp
TDZ=/sys/class/thermal/thermal_zone0
OUT_LOG=/data/local/tmp/e9_long_${LABEL}.log
TH_LOG=/data/local/tmp/e9_long_${LABEL}.thermal.txt

echo "START temp=$(cat $TDZ/temp)" > "$TH_LOG"
echo "label=$LABEL n_gen=$NGEN" >> "$TH_LOG"

# sampleur thermique (processus propre, pas le bench) - 2s
(
  i=0
  while [ $i -lt $DUR ]; do
    T=$(cat $TDZ/temp 2>/dev/null)
    NS=$(for z in $TDZ/thermal_zone*; do ty=$(cat $z/type 2>/dev/null); case "$ty" in nsphvx-*) printf "%s " "$(cat $z/temp)";; esac; done)
    echo "t=${i}s T0=$T nsphvx=[$NS]" >> "$TH_LOG"
    i=$((i+2)); sleep 2
  done
) &
SAMP=$!

# bench en foreground (le vrai job)
LD_LIBRARY_PATH=/data/local/tmp/qairt:/data/local/tmp/gxlibs:/data/local/tmp:/vendor/lib64:/system/lib64 \
ADSP_LIBRARY_PATH=/data/local/tmp \
./geniex-bench --plugin qairt --device npu -m /data/local/tmp/qwen3-8b-w4a16 -p 128 -n "$NGEN" -r 1 \
  --prompt-file /data/local/tmp/e9_prompt.txt > "$OUT_LOG" 2>&1
RC=$?

kill $SAMP 2>/dev/null
sleep 1
echo "END temp=$(cat $TDZ/temp) rc=$RC" >> "$TH_LOG"
echo "== resume ==" >> "$TH_LOG"
grep -aoE "decode=[0-9.]+|gen=[0-9]+|ttft=[0-9.]+ms|prefill=[0-9.]+" "$OUT_LOG" | tail -4 >> "$TH_LOG"
echo "done"